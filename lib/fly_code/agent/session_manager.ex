defmodule FlyCode.Agent.SessionManager do
  @moduledoc """
  GenServer that runs ON a FLAME runner.
  Owns the agent session and workspace for a single agent session.
  Delegates to a backend adapter (ClaudeCode or OpenCode) for SDK interactions.
  """

  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def send_message(pid, text), do: GenServer.cast(pid, {:message, text})

  def get_messages(pid), do: GenServer.call(pid, :get_messages)

  @impl true
  def init(opts) do
    Logger.info("[SessionManager] init called with session_id=#{Keyword.get(opts, :session_id)}")

    session_id = Keyword.fetch!(opts, :session_id)
    pubsub_topic = Keyword.fetch!(opts, :pubsub_topic)
    backend = Keyword.get(opts, :backend, :claude_code)

    state = %{
      client: nil,
      backend_mod: backend_module(backend),
      session_id: session_id,
      workspace: nil,
      pubsub_topic: pubsub_topic,
      task: nil,
      messages: [],
      # Stored for handle_continue
      repo_url: Keyword.fetch!(opts, :repo_url),
      env_vars: Keyword.fetch!(opts, :env_vars),
      branch: Keyword.get(opts, :branch, "main"),
      backend: backend,
      setup_script: Keyword.get(opts, :setup_script)
    }

    :pg.join(FlyCode.PG, {:session, session_id}, self())

    {:ok, state, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    # Broadcast cloning status
    broadcast(state.pubsub_topic, {:status, :cloning})

    # Inject env vars into the runner's process environment
    FlyCode.Workspace.inject_env_vars(state.env_vars)

    # Clone repo
    Logger.info("[SessionManager] cloning #{state.repo_url} (branch: #{state.branch})")

    with {:ok, workspace_path} <-
           FlyCode.Workspace.setup(state.repo_url, state.session_id, branch: state.branch),
         :ok <- maybe_run_setup_script(workspace_path, state.setup_script, state.pubsub_topic),
         :ok <- Logger.info("[SessionManager] clone complete, starting #{state.backend} backend"),
         {:ok, client} <-
           state.backend_mod.start(state.session_id, workspace_path, state.pubsub_topic) do
      Logger.info("[SessionManager] backend started successfully")
      FlyCode.Agent.Coordinator.update_session_status(state.session_id, :active)
      broadcast(state.pubsub_topic, {:status, :active})

      {:noreply,
       %{state | client: client, workspace: workspace_path, repo_url: nil, env_vars: nil}}
    else
      {:error, {:setup_script, reason}} ->
        Logger.error("[SessionManager] setup script FAILED: #{reason}")
        broadcast(state.pubsub_topic, {:error, "Setup script failed: #{reason}"})
        {:stop, {:setup_script_failed, reason}, state}

      {:error, reason} when is_binary(reason) ->
        Logger.error("[SessionManager] clone FAILED: #{reason}")
        broadcast(state.pubsub_topic, {:error, "Failed to clone repo: #{reason}"})
        {:stop, {:clone_failed, reason}, state}

      {:error, reason} ->
        Logger.error("[SessionManager] backend start FAILED: #{inspect(reason)}")
        broadcast(state.pubsub_topic, {:error, "Failed to start backend: #{inspect(reason)}"})
        {:stop, {:backend_start_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  @impl true
  def handle_cast({:message, text}, state) do
    user_msg = %{id: System.unique_integer([:positive]), role: :user, content: text}
    me = self()

    task =
      Task.async(fn ->
        try do
          events =
            state.backend_mod.stream(state.client, text)
            |> Enum.map(fn event ->
              broadcast(state.pubsub_topic, {:agent_event, event})
              event
            end)

          broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
          send(me, {:store_events, events})
        catch
          :throw, {:stream_init_error, reason} ->
            Logger.error("Stream init failed: #{inspect(reason)}")

            broadcast(
              state.pubsub_topic,
              {:agent_event, {:error, "Agent failed to start: #{inspect(reason)}"}}
            )

            broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
        end
      end)

    {:noreply, %{state | task: task, messages: state.messages ++ [user_msg]}}
  end

  @impl true
  def handle_info({:store_events, events}, state) do
    messages = state.messages ++ events_to_messages(events)
    {:noreply, %{state | messages: messages}}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | task: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Agent task crashed: #{inspect(reason)}")
    broadcast(state.pubsub_topic, {:agent_event, {:error, inspect(reason)}})
    {:noreply, %{state | task: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    state.backend_mod.stop(state.client)
  end

  defp events_to_messages(events) do
    # Collapse text deltas into a single assistant message, keep tool events
    events
    |> Enum.reduce({[], ""}, fn
      {:text_delta, delta}, {msgs, acc_text} ->
        {msgs, acc_text <> delta}

      {:text, text}, {msgs, acc_text} ->
        {msgs, acc_text <> text}

      {:tool_use_start, name, input}, {msgs, acc_text} ->
        msgs = maybe_flush_text(msgs, acc_text)

        tool_msg = %{
          id: System.unique_integer([:positive]),
          role: :tool,
          tool_name: name,
          content: inspect(input)
        }

        {msgs ++ [tool_msg], ""}

      {:tool_result, _name, output}, {msgs, acc_text} ->
        # Update the last tool message with the result
        msgs = update_last_tool_msg(msgs, output)
        {msgs, acc_text}

      {:error, message}, {msgs, acc_text} ->
        msgs = maybe_flush_text(msgs, acc_text)
        {msgs ++ [%{id: System.unique_integer([:positive]), role: :error, content: message}], ""}

      _other, acc ->
        acc
    end)
    |> then(fn {msgs, acc_text} -> maybe_flush_text(msgs, acc_text) end)
  end

  defp maybe_flush_text(msgs, ""), do: msgs

  defp maybe_flush_text(msgs, text) do
    msgs ++ [%{id: System.unique_integer([:positive]), role: :assistant, content: text}]
  end

  defp update_last_tool_msg(msgs, output) do
    case List.pop_at(msgs, -1) do
      {%{role: :tool} = tool_msg, rest} -> rest ++ [%{tool_msg | content: output}]
      _ -> msgs
    end
  end

  defp maybe_run_setup_script(_workspace_path, nil, _topic), do: :ok
  defp maybe_run_setup_script(_workspace_path, "", _topic), do: :ok

  defp maybe_run_setup_script(workspace_path, script, topic) do
    broadcast(topic, {:status, :setup})

    case FlyCode.Workspace.run_setup_script(workspace_path, script) do
      :ok -> :ok
      {:error, output} -> {:error, {:setup_script, output}}
    end
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(FlyCode.PubSub, topic, message)
  end

  defp backend_module(:claude_code), do: FlyCode.Agent.Backends.ClaudeCode
  defp backend_module(:opencode), do: FlyCode.Agent.Backends.OpenCode
end

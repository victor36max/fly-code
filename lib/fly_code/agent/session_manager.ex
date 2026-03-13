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
    IO.puts("[SessionManager] init called with session_id=#{Keyword.get(opts, :session_id)}")

    repo_url = Keyword.fetch!(opts, :repo_url)
    session_id = Keyword.fetch!(opts, :session_id)
    pubsub_topic = Keyword.fetch!(opts, :pubsub_topic)
    env_vars = Keyword.fetch!(opts, :env_vars)
    branch = Keyword.get(opts, :branch, "main")
    backend = Keyword.get(opts, :backend, :claude_code)
    backend_mod = backend_module(backend)

    # Broadcast cloning status
    broadcast(pubsub_topic, {:status, :cloning})

    # Inject env vars into the runner's process environment
    FlyCode.Workspace.inject_env_vars(env_vars)

    # Clone repo
    IO.puts("[SessionManager] cloning #{repo_url} (branch: #{branch})")

    case FlyCode.Workspace.setup(repo_url, session_id, branch: branch) do
      {:ok, workspace_path} ->
        IO.puts("[SessionManager] clone complete, starting #{backend} backend")

        case backend_mod.start(session_id, workspace_path, pubsub_topic) do
          {:ok, client} ->
            IO.puts("[SessionManager] backend started successfully")
            broadcast(pubsub_topic, {:status, :active})

            {:ok,
             %{
               client: client,
               backend_mod: backend_mod,
               session_id: session_id,
               workspace: workspace_path,
               pubsub_topic: pubsub_topic,
               task: nil,
               messages: []
             }}

          {:error, reason} ->
            IO.puts("[SessionManager] backend start FAILED: #{inspect(reason)}")
            broadcast(pubsub_topic, {:error, "Failed to start backend: #{inspect(reason)}"})
            {:stop, {:backend_start_failed, reason}}
        end

      {:error, reason} ->
        IO.puts("[SessionManager] clone FAILED: #{reason}")
        broadcast(pubsub_topic, {:error, "Failed to clone repo: #{reason}"})
        {:stop, {:clone_failed, reason}}
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
        events =
          state.backend_mod.stream(state.client, text)
          |> Enum.map(fn event ->
            broadcast(state.pubsub_topic, {:agent_event, event})
            event
          end)

        broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
        send(me, {:store_events, events})
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

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(FlyCode.PubSub, topic, message)
  end

  defp backend_module(:claude_code), do: FlyCode.Agent.Backends.ClaudeCode
  defp backend_module(:opencode), do: FlyCode.Agent.Backends.OpenCode
end

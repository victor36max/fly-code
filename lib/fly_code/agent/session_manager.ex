defmodule FlyCode.Agent.SessionManager do
  @moduledoc """
  GenServer that runs ON a FLAME runner.
  Owns the agent session and workspace for a single agent session.
  Delegates to a backend adapter (ClaudeCode or OpenCode) for SDK interactions.

  ## State Machine

      spawning → cloning → setup_script → spawning_agent → active → completed
                                                                   ↘ shutdown
                     ↘ failed (any setup phase can transition here on error)
  """

  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def send_message(pid, text), do: GenServer.cast(pid, {:message, text})
  def set_model(pid, model), do: GenServer.cast(pid, {:set_model, model})
  def set_mode(pid, mode), do: GenServer.cast(pid, {:set_mode, mode})
  def interrupt(pid), do: GenServer.cast(pid, :interrupt)

  def get_messages(pid), do: GenServer.call(pid, :get_messages, 15_000)

  def get_setup_state(pid), do: GenServer.call(pid, :get_setup_state, 15_000)

  @impl true
  def init(opts) do
    Logger.info("[SessionManager] init called with session_id=#{Keyword.get(opts, :session_id)}")

    session_id = Keyword.fetch!(opts, :session_id)
    pubsub_topic = Keyword.fetch!(opts, :pubsub_topic)
    backend = Keyword.get(opts, :backend, :claude_code)

    state = %{
      phase: :spawning,
      client: nil,
      backend_mod: backend_module(backend),
      session_id: session_id,
      workspace: nil,
      pubsub_topic: pubsub_topic,
      task: nil,
      messages: [],
      setup_output: [],
      # Stored for handle_continue
      repo_url: Keyword.fetch!(opts, :repo_url),
      env_vars: Keyword.fetch!(opts, :env_vars),
      branch: Keyword.get(opts, :branch, "main"),
      backend: backend,
      setup_script: Keyword.get(opts, :setup_script),
      current_model: nil,
      current_mode: :build
    }

    :pg.join(FlyCode.PG, {:session, session_id}, self())

    broadcast(state.pubsub_topic, {:status, state.session_id, :spawning})
    {:ok, state, {:continue, :clone}}
  end

  # --- Phase transitions via handle_continue ---

  @impl true
  def handle_continue(:clone, state) do
    state = transition(state, :cloning)

    # Inject env vars into the runner's process environment
    FlyCode.Workspace.inject_env_vars(state.env_vars)

    clone_task =
      Task.async(fn ->
        Logger.info("[SessionManager] cloning #{state.repo_url} (branch: #{state.branch})")

        case FlyCode.Workspace.setup(state.repo_url, state.session_id, branch: state.branch) do
          {:ok, workspace_path} -> {:ok, :clone_complete, workspace_path}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:noreply, %{state | task: clone_task}}
  end

  def handle_continue(:run_setup_script, state) do
    state = transition(state, :setup_script)
    pubsub_topic = state.pubsub_topic
    me = self()

    setup_task =
      Task.async(fn ->
        on_output = fn line ->
          broadcast(pubsub_topic, {:setup_output, line})
          send(me, {:setup_output_line, line})
        end

        case FlyCode.Workspace.stream_setup_script(state.workspace, state.setup_script, on_output) do
          :ok -> {:ok, :setup_complete}
          {:error, output} -> {:error, {:setup_script, output}}
        end
      end)

    {:noreply, %{state | task: setup_task}}
  end

  def handle_continue(:start_backend, state) do
    state = transition(state, :spawning_agent)

    backend_task =
      Task.async(fn ->
        case state.backend_mod.start(state.session_id, state.workspace, state.pubsub_topic) do
          {:ok, client} -> {:ok, :backend_ready, client}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:noreply, %{state | task: backend_task}}
  end

  # --- Synchronous calls ---

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:get_setup_state, _from, state) do
    {:reply, state.setup_output, state}
  end

  # --- Message handling ---

  @impl true
  def handle_cast({:message, _text}, %{phase: phase} = state)
      when phase != :active do
    Logger.warning("[SessionManager] ignoring message — session in phase #{phase}")
    {:noreply, state}
  end

  def handle_cast({:message, text}, state) do
    user_msg = %{id: System.unique_integer([:positive]), role: :user, content: text}
    state = %{state | messages: state.messages ++ [user_msg]}
    {:noreply, start_stream(state, text)}
  end

  def handle_cast({:set_model, model}, %{phase: :active} = state) do
    case safe_backend_call(fn -> state.backend_mod.set_model(state.client, model) end) do
      :ok ->
        broadcast(state.pubsub_topic, {:model_changed, model})
        {:noreply, %{state | current_model: model}}

      {:error, reason} ->
        Logger.warning("[SessionManager] set_model failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:set_model, _model}, state), do: {:noreply, state}

  def handle_cast({:set_mode, mode}, %{phase: :active} = state) do
    case safe_backend_call(fn -> state.backend_mod.set_mode(state.client, mode) end) do
      :ok ->
        broadcast(state.pubsub_topic, {:mode_changed, mode})
        {:noreply, %{state | current_mode: mode}}

      {:error, reason} ->
        Logger.warning("[SessionManager] set_mode failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:set_mode, _mode}, state), do: {:noreply, state}

  def handle_cast(:interrupt, %{phase: :active, task: %Task{} = task} = state) do
    safe_backend_call(fn -> state.backend_mod.interrupt(state.client) end)
    Task.shutdown(task, :brutal_kill)
    broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
    {:noreply, %{state | task: nil}}
  end

  def handle_cast(:interrupt, state), do: {:noreply, state}

  defp start_stream(state, text) do
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
          :throw, {error_type, {:provisioning_failed, _} = reason}
          when error_type in [:stream_init_error, :stream_error] ->
            Logger.warning(
              "Stream failed with provisioning error, restarting backend: #{inspect(reason)}"
            )

            send(me, {:restart_backend_and_retry, text})

          :throw, {:stream_init_error, reason} ->
            Logger.error("Stream init failed: #{inspect(reason)}")

            broadcast(
              state.pubsub_topic,
              {:agent_event, {:error, "Agent failed to start: #{inspect(reason)}"}}
            )

            broadcast(state.pubsub_topic, {:agent_event, :turn_complete})

          :throw, {:stream_error, reason} ->
            Logger.error("Stream error: #{inspect(reason)}")

            broadcast(
              state.pubsub_topic,
              {:agent_event, {:error, "Agent stream error: #{inspect(reason)}"}}
            )

            broadcast(state.pubsub_topic, {:agent_event, :turn_complete})

          kind, reason ->
            Logger.error("Stream unexpected #{kind}: #{inspect(reason)}")

            broadcast(
              state.pubsub_topic,
              {:agent_event, {:error, "Agent error: #{inspect(reason)}"}}
            )

            broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
        end
      end)

    %{state | task: task}
  end

  # --- Task completion handlers ---

  @impl true
  def handle_info({:setup_output_line, line}, state) do
    {:noreply, %{state | setup_output: state.setup_output ++ [line]}}
  end

  def handle_info({:store_events, events}, state) do
    messages = state.messages ++ events_to_messages(events)
    {:noreply, %{state | messages: messages}}
  end

  # Backend provisioning failed mid-stream — restart the client and retry the message
  def handle_info({:restart_backend_and_retry, text}, state) do
    Logger.info("[SessionManager] restarting backend for #{state.session_id}")
    safe_backend_call(fn -> state.backend_mod.stop(state.client) end)

    case safe_backend_call(fn -> state.backend_mod.start(state.session_id, state.workspace, state.pubsub_topic) end) do
      {:ok, new_client} ->
        Logger.info("[SessionManager] backend restarted, retrying message")
        {:noreply, start_stream(%{state | client: new_client, task: nil}, text)}

      {:error, reason} ->
        Logger.error("[SessionManager] backend restart failed: #{inspect(reason)}")

        broadcast(
          state.pubsub_topic,
          {:agent_event, {:error, "Agent restart failed: #{inspect(reason)}"}}
        )

        broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
        {:noreply, %{state | task: nil}}
    end
  end

  # Clone complete → run setup script (or skip to start_backend)
  def handle_info({ref, {:ok, :clone_complete, workspace_path}}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Logger.info("[SessionManager] clone complete")

    state = %{state | workspace: workspace_path, task: nil, repo_url: nil, env_vars: nil}

    next_continue =
      if state.setup_script && state.setup_script != "" do
        :run_setup_script
      else
        :start_backend
      end

    {:noreply, state, {:continue, next_continue}}
  end

  # Setup script complete → start backend
  def handle_info({ref, {:ok, :setup_complete}}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Logger.info("[SessionManager] setup script complete")
    {:noreply, %{state | task: nil}, {:continue, :start_backend}}
  end

  # Backend ready → active
  def handle_info({ref, {:ok, :backend_ready, client}}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Logger.info("[SessionManager] backend started successfully")

    state =
      state
      |> Map.put(:client, client)
      |> Map.put(:task, nil)
      |> transition(:active)

    {:noreply, state}
  end

  # Any setup phase task failed
  def handle_info({ref, {:error, reason}}, %{task: %Task{ref: ref}, phase: phase} = state)
      when phase in [:cloning, :setup_script, :spawning_agent] do
    Process.demonitor(ref, [:flush])
    {log_msg, user_msg} = format_setup_error(reason)
    Logger.error(log_msg)

    state = transition(state, :failed)
    broadcast(state.pubsub_topic, {:error, user_msg})

    {:stop, {:setup_failed, reason}, state}
  end

  # Agent streaming task completed (not a phase transition)
  def handle_info({ref, _result}, %{phase: :active} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | task: nil}}
  end

  # Catch-all for other task completions
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | task: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Agent task crashed: #{inspect(reason)}")
    broadcast(state.pubsub_topic, {:agent_event, {:error, inspect(reason)}})
    broadcast(state.pubsub_topic, {:agent_event, :turn_complete})
    {:noreply, %{state | task: nil}}
  end

  # --- Terminate ---

  @impl true
  def terminate(_reason, %{client: nil}), do: :ok

  def terminate(_reason, state) do
    safe_backend_call(fn -> state.backend_mod.stop(state.client) end)
    :ok
  end

  # --- Private helpers ---

  defp transition(state, new_phase) do
    Logger.info("[SessionManager] #{state.session_id}: #{state.phase} → #{new_phase}")
    broadcast(state.pubsub_topic, {:status, state.session_id, new_phase})
    %{state | phase: new_phase}
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

  defp format_setup_error({:setup_script, reason}) do
    {"[SessionManager] setup script FAILED: #{reason}", "Setup script failed: #{reason}"}
  end

  defp format_setup_error(reason) when is_binary(reason) do
    {"[SessionManager] setup FAILED: #{reason}", "Failed to set up session: #{reason}"}
  end

  defp format_setup_error(reason) do
    {"[SessionManager] setup FAILED: #{inspect(reason)}",
     "Failed to start backend: #{inspect(reason)}"}
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(FlyCode.PubSub, topic, message)
  end

  defp safe_backend_call(fun) do
    fun.()
  rescue
    e ->
      Logger.warning("[SessionManager] backend call raised: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  catch
    :exit, {:timeout, _} ->
      Logger.warning("[SessionManager] backend call timed out")
      {:error, :timeout}

    :exit, reason ->
      Logger.warning("[SessionManager] backend call failed: #{inspect(reason)}")
      {:error, reason}
  end

  defp backend_module(:claude_code), do: FlyCode.Agent.Backends.ClaudeCode
  defp backend_module(:opencode), do: FlyCode.Agent.Backends.OpenCode
end

defmodule FlyCode.Agent.Coordinator do
  @moduledoc """
  Session registry running on the main VM.
  Maps session_ids to their remote SessionManager pids on FLAME runners.
  Resolves and decrypts env vars before passing to runners.
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_session(project_id, opts \\ []) do
    GenServer.call(__MODULE__, {:start_session, project_id, opts}, :timer.minutes(3))
  end

  def send_message(session_id, text) do
    with_session(session_id, &FlyCode.Agent.SessionManager.send_message(&1, text))
  end

  def set_model(session_id, model) do
    with_session(session_id, &FlyCode.Agent.SessionManager.set_model(&1, model))
  end

  def set_mode(session_id, mode) do
    with_session(session_id, &FlyCode.Agent.SessionManager.set_mode(&1, mode))
  end

  def interrupt(session_id) do
    with_session(session_id, &FlyCode.Agent.SessionManager.interrupt/1)
  end

  defp with_session(session_id, fun) do
    case GenServer.call(__MODULE__, {:lookup, session_id}) do
      {:ok, pid} ->
        fun.(pid)
        :ok

      :not_found ->
        {:error, :session_not_found}
    end
  end

  def get_messages(session_id) do
    case GenServer.call(__MODULE__, {:lookup, session_id}) do
      {:ok, pid} ->
        try do
          {:ok, FlyCode.Agent.SessionManager.get_messages(pid)}
        catch
          :exit, _ -> {:error, :timeout}
        end

      :not_found ->
        {:error, :session_not_found}
    end
  end

  def get_setup_state(session_id) do
    case GenServer.call(__MODULE__, {:lookup, session_id}) do
      {:ok, pid} ->
        try do
          {:ok, FlyCode.Agent.SessionManager.get_setup_state(pid)}
        catch
          :exit, _ -> {:error, :timeout}
        end

      :not_found ->
        {:error, :session_not_found}
    end
  end

  def list_active_sessions do
    GenServer.call(__MODULE__, :list_active)
  end

  # --- Callbacks ---

  @impl true
  def init(_) do
    sessions = recover_sessions()
    {:ok, %{sessions: sessions}}
  end

  defp recover_sessions do
    recovered =
      :pg.which_groups(FlyCode.PG)
      |> Enum.reduce(%{}, fn
        {:session, session_id}, acc ->
          case :pg.get_members(FlyCode.PG, {:session, session_id}) do
            [pid | _] ->
              case FlyCode.Sessions.get_session_by_session_id(session_id) do
                nil ->
                  acc

                db_session ->
                  Process.monitor(pid)
                  Phoenix.PubSub.subscribe(FlyCode.PubSub, "session:#{session_id}")
                  Logger.info("Recovered session #{session_id} from pg (pid: #{inspect(pid)})")
                  Map.put(acc, session_id, %{pid: pid, project_id: db_session.project_id})
              end

            [] ->
              acc
          end

        _other_group, acc ->
          acc
      end)

    recovered_ids = recovered |> Map.keys() |> MapSet.new()
    FlyCode.Sessions.shutdown_unrecovered_sessions(recovered_ids)

    recovered
  end

  @impl true
  def handle_call({:start_session, project_id, opts}, _from, state) do
    project = FlyCode.Projects.get_project!(project_id)
    session_id = Ecto.UUID.generate()
    pubsub_topic = "session:#{session_id}"

    # Resolve global + project env vars (decrypted by Cloak automatically)
    env_vars = FlyCode.Projects.resolve_env_vars(project_id)

    backend = Keyword.get(opts, :backend, :claude_code)

    branch = Keyword.get(opts, :branch, project.default_branch)

    # Persist session BEFORE placing on FLAME, so SessionManager can update its status
    {:ok, _session} =
      FlyCode.Sessions.create_session(%{
        session_id: session_id,
        project_id: project_id,
        status: :spawning,
        branch: branch,
        backend: backend
      })

    child_opts = [
      repo_url: project.repo_url,
      session_id: session_id,
      pubsub_topic: pubsub_topic,
      env_vars: env_vars,
      branch: branch,
      backend: backend,
      setup_script: project.setup_script
    ]

    # Subscribe BEFORE placing the child to avoid missing status broadcasts
    Phoenix.PubSub.subscribe(FlyCode.PubSub, pubsub_topic)

    case FLAME.place_child(FlyCode.AgentPool, {FlyCode.Agent.SessionManager, child_opts}) do
      {:ok, pid} ->
        Process.monitor(pid)

        sessions = Map.put(state.sessions, session_id, %{pid: pid, project_id: project_id})

        {:reply, {:ok, %{session_id: session_id, pid: pid, topic: pubsub_topic}},
         %{state | sessions: sessions}}

      {:error, reason} ->
        Phoenix.PubSub.unsubscribe(FlyCode.PubSub, pubsub_topic)
        Logger.error("Failed to place session on FLAME runner: #{inspect(reason)}")
        FlyCode.Sessions.update_session_status(session_id, :shutdown)
        {:reply, {:error, reason}, state}

      other ->
        Phoenix.PubSub.unsubscribe(FlyCode.PubSub, pubsub_topic)
        Logger.error("Unexpected place_child result: #{inspect(other)}")
        FlyCode.Sessions.update_session_status(session_id, :shutdown)
        {:reply, {:error, :unexpected_result}, state}
    end
  end

  def handle_call({:lookup, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      %{pid: pid} -> {:reply, {:ok, pid}, state}
      nil -> {:reply, :not_found, state}
    end
  end

  def handle_call(:list_active, _from, state) do
    {:reply, state.sessions, state}
  end

  @impl true
  def handle_info({:status, session_id, status}, state)
      when is_binary(session_id) and is_atom(status) do
    Logger.info("[Coordinator] Received status update: #{session_id} -> #{status}")
    result = FlyCode.Sessions.update_session_status(session_id, status)
    Logger.info("[Coordinator] DB update result: #{inspect(result)}")
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find and remove the session whose pid went down
    case Enum.find(state.sessions, fn {_id, %{pid: p}} -> p == pid end) do
      {session_id, _info} ->
        Logger.info("Session #{session_id} runner went down: #{inspect(reason)}")
        FlyCode.Sessions.update_session_status(session_id, :shutdown)

        Phoenix.PubSub.broadcast_from(
          FlyCode.PubSub,
          self(),
          "session:#{session_id}",
          {:status, session_id, :shutdown}
        )

        sessions = Map.delete(state.sessions, session_id)
        {:noreply, %{state | sessions: sessions}}

      nil ->
        {:noreply, state}
    end
  end

  # Ignore other PubSub messages (agent_event, error, etc.)
  def handle_info(_msg, state), do: {:noreply, state}
end

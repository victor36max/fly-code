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
    case GenServer.call(__MODULE__, {:lookup, session_id}) do
      {:ok, pid} ->
        FlyCode.Agent.SessionManager.send_message(pid, text)
        :ok

      :not_found ->
        {:error, :session_not_found}
    end
  end

  def get_messages(session_id) do
    case GenServer.call(__MODULE__, {:lookup, session_id}) do
      {:ok, pid} -> {:ok, FlyCode.Agent.SessionManager.get_messages(pid)}
      :not_found -> {:error, :session_not_found}
    end
  end

  def list_active_sessions do
    GenServer.call(__MODULE__, :list_active)
  end

  # --- Callbacks ---

  @impl true
  def init(_) do
    FlyCode.Sessions.shutdown_stale_sessions()
    {:ok, %{sessions: %{}}}
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
        status: :cloning,
        branch: branch,
        backend: backend
      })

    child_opts = [
      repo_url: project.repo_url,
      session_id: session_id,
      pubsub_topic: pubsub_topic,
      env_vars: env_vars,
      branch: branch,
      backend: backend
    ]

    case FLAME.place_child(FlyCode.AgentPool, {FlyCode.Agent.SessionManager, child_opts}) do
      {:ok, pid} ->
        # Monitor the remote process
        Process.monitor(pid)

        # Update status in DB (Repo runs on the main VM, not on FLAME runners)
        FlyCode.Sessions.update_session_status(session_id, :active)

        sessions = Map.put(state.sessions, session_id, %{pid: pid, project_id: project_id})

        {:reply, {:ok, %{session_id: session_id, pid: pid, topic: pubsub_topic}},
         %{state | sessions: sessions}}

      {:error, reason} ->
        Logger.error("Failed to place session on FLAME runner: #{inspect(reason)}")
        FlyCode.Sessions.update_session_status(session_id, :shutdown)
        {:reply, {:error, reason}, state}

      other ->
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
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find and remove the session whose pid went down
    case Enum.find(state.sessions, fn {_id, %{pid: p}} -> p == pid end) do
      {session_id, _info} ->
        Logger.info("Session #{session_id} runner went down: #{inspect(reason)}")
        FlyCode.Sessions.update_session_status(session_id, :shutdown)
        sessions = Map.delete(state.sessions, session_id)
        {:noreply, %{state | sessions: sessions}}

      nil ->
        {:noreply, state}
    end
  end
end

defmodule FlyCode.Agent.CoordinatorTest do
  use FlyCode.DataCase, async: false

  alias FlyCode.Agent.Coordinator

  setup do
    # Use the app-level Coordinator directly — it's already running.
    # Clean up state before each test.
    :sys.replace_state(Coordinator, fn _state -> %{sessions: %{}} end)

    on_exit(fn ->
      :sys.replace_state(Coordinator, fn _state -> %{sessions: %{}} end)
    end)

    :ok
  end

  describe "init/1" do
    test "starts with empty sessions" do
      state = :sys.get_state(Coordinator)
      assert state.sessions == %{}
    end
  end

  describe "lookup" do
    test "returns {:ok, pid} for existing session" do
      fake_pid = self()

      :sys.replace_state(Coordinator, fn state ->
        %{state | sessions: Map.put(state.sessions, "sess-1", %{pid: fake_pid, project_id: 1})}
      end)

      assert {:ok, ^fake_pid} = GenServer.call(Coordinator, {:lookup, "sess-1"})
    end

    test "returns :not_found for missing session" do
      assert :not_found = GenServer.call(Coordinator, {:lookup, "nonexistent"})
    end
  end

  describe "list_active" do
    test "returns the sessions map" do
      :sys.replace_state(Coordinator, fn state ->
        %{state | sessions: %{"s1" => %{pid: self(), project_id: 1}}}
      end)

      sessions = GenServer.call(Coordinator, :list_active)
      assert map_size(sessions) == 1
      assert Map.has_key?(sessions, "s1")
    end

    test "returns empty map when no sessions" do
      assert %{} = GenServer.call(Coordinator, :list_active)
    end
  end

  describe "recovery via :pg" do
    test "recovers session from pg group on restart" do
      project = FlyCode.Fixtures.project_fixture()
      session_id = Ecto.UUID.generate()

      {:ok, _session} =
        FlyCode.Sessions.create_session(%{
          session_id: session_id,
          status: :active,
          project_id: project.id
        })

      # Simulate a SessionManager registering in pg
      dummy = spawn(fn -> Process.sleep(:infinity) end)
      :pg.join(FlyCode.PG, {:session, session_id}, dummy)

      # Restart the Coordinator to trigger recovery
      :sys.replace_state(Coordinator, fn _state -> %{sessions: %{}} end)
      # Manually call the recovery by restarting init behavior
      GenServer.stop(Coordinator, :normal)
      # Wait for supervisor to restart it
      Process.sleep(100)

      state = :sys.get_state(Coordinator)
      assert %{pid: ^dummy, project_id: project_id} = Map.get(state.sessions, session_id)
      assert project_id == project.id

      # Cleanup
      Process.exit(dummy, :kill)
    end

    test "marks unrecovered sessions as shutdown" do
      project = FlyCode.Fixtures.project_fixture()

      {:ok, session} =
        FlyCode.Sessions.create_session(%{
          session_id: Ecto.UUID.generate(),
          status: :active,
          project_id: project.id
        })

      # No pg registration — session should be marked shutdown on recovery
      GenServer.stop(Coordinator, :normal)
      Process.sleep(100)

      updated = FlyCode.Sessions.get_session_by_session_id(session.session_id)
      assert updated.status == :shutdown
    end
  end

  describe "handle_info :DOWN" do
    test "removes session when its process goes down" do
      # Spawn a process we can kill
      {:ok, dummy} = Task.start(fn -> Process.sleep(:infinity) end)
      # replace_state runs inside the GenServer process, so Process.monitor
      # will correctly make the Coordinator receive the :DOWN message
      :sys.replace_state(Coordinator, fn state ->
        Process.monitor(dummy)
        %{state | sessions: %{"sess-down" => %{pid: dummy, project_id: 1}}}
      end)

      # Create a session record so update_session_status doesn't error
      project = FlyCode.Fixtures.project_fixture()

      {:ok, _} =
        FlyCode.Sessions.create_session(%{
          session_id: "sess-down",
          status: :active,
          project_id: project.id
        })

      # Kill the dummy process
      Process.exit(dummy, :kill)

      # Wait for the Coordinator to process the DOWN message
      # :sys.get_state is synchronous, so after it returns, the DOWN has been processed
      _ = :sys.get_state(Coordinator)
      # Need a second call since DOWN might be queued after the first get_state
      Process.sleep(50)
      _ = :sys.get_state(Coordinator)

      state = :sys.get_state(Coordinator)
      assert state.sessions == %{}
    end
  end
end

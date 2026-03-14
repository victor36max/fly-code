defmodule FlyCode.Agent.SessionManagerTest do
  use FlyCode.DataCase, async: false

  alias FlyCode.Agent.SessionManager

  # A fake backend that records calls via message passing
  defmodule FakeBackend do
    def start(_session_id, _workspace, _topic) do
      {:ok, :fake_client}
    end

    def stream(_client, _text) do
      [{:text, "hello"}]
    end

    def stop(_client), do: :ok

    def set_model(_client, _model), do: :ok
    def set_mode(_client, _mode), do: :ok
    def interrupt(_client), do: :ok
  end

  defmodule CrashingBackend do
    def start(_session_id, _workspace, _topic), do: {:ok, :crash_client}
    def stream(_client, _text), do: [{:text, "hi"}]
    def stop(_client), do: exit(:brutal)
    def set_model(_client, _model), do: exit({:timeout, {GenServer, :call, [:fake]}})
    def set_mode(_client, _mode), do: raise("boom")
    def interrupt(_client), do: exit(:brutal)
  end

  defp start_active_manager(opts \\ []) do
    backend_mod = Keyword.get(opts, :backend_mod, FakeBackend)
    session_id = Keyword.get(opts, :session_id, Ecto.UUID.generate())
    topic = "session:#{session_id}"

    Phoenix.PubSub.subscribe(FlyCode.PubSub, topic)

    # Start with a minimal init and immediately replace state to :active
    pid =
      start_supervised!(
        {SessionManager,
         [
           session_id: session_id,
           pubsub_topic: topic,
           repo_url: "https://example.com/repo.git",
           env_vars: %{},
           branch: "main",
           backend: :claude_code,
           setup_script: nil
         ]}
      )

    # Jump straight to :active phase with a fake client
    :sys.replace_state(pid, fn state ->
      %{state | phase: :active, client: :fake_client, backend_mod: backend_mod, task: nil}
    end)

    # Drain the setup phase broadcasts
    drain_messages()

    %{pid: pid, session_id: session_id, topic: topic}
  end

  defp drain_messages do
    receive do
      _ -> drain_messages()
    after
      50 -> :ok
    end
  end

  describe "set_model/2" do
    test "broadcasts model_changed when backend succeeds" do
      %{pid: pid} = start_active_manager()

      SessionManager.set_model(pid, "opus")

      assert_receive {:model_changed, "opus"}, 1000

      state = :sys.get_state(pid)
      assert state.current_model == "opus"
    end

    test "does not crash when backend times out" do
      %{pid: pid} = start_active_manager(backend_mod: CrashingBackend)

      SessionManager.set_model(pid, "opus")

      # Give the cast time to process
      _ = :sys.get_state(pid)

      # Process should still be alive
      assert Process.alive?(pid)

      # Model should NOT have changed
      state = :sys.get_state(pid)
      assert state.current_model != "opus"
    end

    test "ignores set_model when not in active phase" do
      %{pid: pid} = start_active_manager()

      :sys.replace_state(pid, fn state -> %{state | phase: :cloning} end)
      drain_messages()

      SessionManager.set_model(pid, "opus")

      # Give the cast time to process
      _ = :sys.get_state(pid)

      refute_receive {:model_changed, _}, 100
    end
  end

  describe "set_mode/2" do
    test "broadcasts mode_changed when backend succeeds" do
      %{pid: pid} = start_active_manager()

      SessionManager.set_mode(pid, :plan)

      assert_receive {:mode_changed, :plan}, 1000

      state = :sys.get_state(pid)
      assert state.current_mode == :plan
    end

    test "does not crash when backend raises" do
      %{pid: pid} = start_active_manager(backend_mod: CrashingBackend)

      SessionManager.set_mode(pid, :plan)

      _ = :sys.get_state(pid)

      assert Process.alive?(pid)
    end

    test "ignores set_mode when not in active phase" do
      %{pid: pid} = start_active_manager()

      :sys.replace_state(pid, fn state -> %{state | phase: :spawning_agent} end)
      drain_messages()

      SessionManager.set_mode(pid, :plan)
      _ = :sys.get_state(pid)

      refute_receive {:mode_changed, _}, 100
    end
  end

  describe "interrupt/1" do
    test "shuts down running task and broadcasts turn_complete" do
      %{pid: pid} = start_active_manager()

      # Create the task inside the GenServer so it owns it (Task.shutdown requires owner)
      :sys.replace_state(pid, fn state ->
        task = Task.async(fn -> Process.sleep(:infinity) end)
        %{state | task: task}
      end)

      SessionManager.interrupt(pid)

      assert_receive {:agent_event, :turn_complete}, 1000

      state = :sys.get_state(pid)
      assert state.task == nil
    end

    test "ignores interrupt when no task is running" do
      %{pid: pid} = start_active_manager()

      SessionManager.interrupt(pid)
      _ = :sys.get_state(pid)

      assert Process.alive?(pid)
    end

    test "ignores interrupt when not in active phase" do
      %{pid: pid} = start_active_manager()

      :sys.replace_state(pid, fn state -> %{state | phase: :cloning} end)
      drain_messages()

      SessionManager.interrupt(pid)
      _ = :sys.get_state(pid)

      refute_receive {:agent_event, :turn_complete}, 100
    end
  end

  describe "terminate/2 safety" do
    test "does not crash when backend stop exits" do
      %{pid: pid} = start_active_manager(backend_mod: CrashingBackend)

      # Stopping should not raise despite CrashingBackend.stop/1 calling exit
      GenServer.stop(pid, :normal)

      refute Process.alive?(pid)
    end
  end

  describe "DOWN handler" do
    test "broadcasts turn_complete when monitored process crashes" do
      %{pid: pid} = start_active_manager()

      # Simulate what happens when a task's process crashes.
      # We send a synthetic :DOWN message to the GenServer.
      fake_ref = make_ref()
      send(pid, {:DOWN, fake_ref, :process, self(), :test_crash})

      assert_receive {:agent_event, :turn_complete}, 1000

      state = :sys.get_state(pid)
      assert state.task == nil
    end
  end

  describe "send_message/2" do
    test "ignores messages when not active" do
      %{pid: pid} = start_active_manager()

      :sys.replace_state(pid, fn state -> %{state | phase: :cloning} end)
      drain_messages()

      SessionManager.send_message(pid, "hello")
      _ = :sys.get_state(pid)

      state = :sys.get_state(pid)
      assert state.messages == []
    end

    test "appends user message and starts streaming when active" do
      %{pid: pid} = start_active_manager()

      SessionManager.send_message(pid, "hello world")

      # Wait for the stream task to complete
      assert_receive {:agent_event, :turn_complete}, 2000

      state = :sys.get_state(pid)
      assert Enum.any?(state.messages, fn msg -> msg.role == :user && msg.content == "hello world" end)
    end
  end
end

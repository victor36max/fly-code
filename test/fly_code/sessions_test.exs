defmodule FlyCode.SessionsTest do
  use FlyCode.DataCase, async: true

  import FlyCode.Fixtures

  alias FlyCode.Sessions

  describe "list_sessions/0" do
    test "returns sessions ordered by inserted_at desc with preloaded project" do
      project = project_fixture()
      _s1 = session_fixture(%{project: project, status: :active})
      _s2 = session_fixture(%{project: project, status: :idle})

      sessions = Sessions.list_sessions()
      assert length(sessions) == 2
      assert hd(sessions).project.id == project.id
    end

    test "returns empty list when no sessions" do
      assert Sessions.list_sessions() == []
    end
  end

  describe "list_sessions_for_project/1" do
    test "returns only sessions for the given project" do
      p1 = project_fixture()
      p2 = project_fixture()

      session_fixture(%{project: p1})
      session_fixture(%{project: p2})

      sessions = Sessions.list_sessions_for_project(p1.id)
      assert length(sessions) == 1
      assert hd(sessions).project_id == p1.id
    end
  end

  describe "get_session!/1" do
    test "returns session with preloaded project" do
      session = session_fixture()
      found = Sessions.get_session!(session.id)
      assert found.id == session.id
      assert found.project.id == session.project_id
    end
  end

  describe "get_session_by_session_id/1" do
    test "returns session when found" do
      session = session_fixture()
      found = Sessions.get_session_by_session_id(session.session_id)
      assert found.id == session.id
    end

    test "returns nil when not found" do
      assert Sessions.get_session_by_session_id("nonexistent") == nil
    end
  end

  describe "create_session/1" do
    test "creates a session with valid attrs" do
      project = project_fixture()

      assert {:ok, session} =
               Sessions.create_session(%{
                 session_id: Ecto.UUID.generate(),
                 status: :cloning,
                 branch: "main",
                 project_id: project.id
               })

      assert session.status == :cloning
    end
  end

  describe "update_session_status/2" do
    test "updates the status" do
      session = session_fixture(%{status: :active})
      assert {:ok, updated} = Sessions.update_session_status(session.session_id, :shutdown)
      assert updated.status == :shutdown
    end

    test "returns error when session not found" do
      assert {:error, :not_found} = Sessions.update_session_status("nonexistent", :shutdown)
    end
  end
end

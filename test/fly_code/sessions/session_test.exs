defmodule FlyCode.Sessions.SessionTest do
  use FlyCode.DataCase, async: true

  import FlyCode.Fixtures

  alias FlyCode.Sessions.Session

  describe "changeset/2" do
    test "valid with required fields" do
      project = project_fixture()

      changeset =
        Session.changeset(%Session{}, %{
          session_id: "abc-123",
          status: :active,
          project_id: project.id
        })

      assert changeset.valid?
    end

    test "requires session_id" do
      project = project_fixture()

      changeset =
        Session.changeset(%Session{}, %{status: :active, project_id: project.id})

      assert %{session_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires status" do
      project = project_fixture()

      changeset =
        Session.changeset(%Session{}, %{session_id: "abc", project_id: project.id})

      assert %{status: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires project_id" do
      changeset =
        Session.changeset(%Session{}, %{session_id: "abc", status: :active})

      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates status enum values" do
      project = project_fixture()

      changeset =
        Session.changeset(%Session{}, %{
          session_id: "abc",
          status: :invalid_status,
          project_id: project.id
        })

      assert %{status: [_]} = errors_on(changeset)
    end

    test "enforces unique session_id constraint" do
      project = project_fixture()
      attrs = %{session_id: "unique-id", status: :active, project_id: project.id}

      {:ok, _} = %Session{} |> Session.changeset(attrs) |> Repo.insert()
      {:error, changeset} = %Session{} |> Session.changeset(attrs) |> Repo.insert()

      assert %{session_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end

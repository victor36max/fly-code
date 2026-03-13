defmodule FlyCode.ProjectsTest do
  use FlyCode.DataCase, async: true

  import FlyCode.Fixtures

  alias FlyCode.Projects

  describe "list_projects/0" do
    test "returns all projects" do
      p1 = project_fixture(%{name: "alpha"})
      p2 = project_fixture(%{name: "beta"})

      projects = Projects.list_projects()
      ids = Enum.map(projects, & &1.id)

      assert p1.id in ids
      assert p2.id in ids
    end

    test "returns empty list when no projects" do
      assert Projects.list_projects() == []
    end
  end

  describe "get_project!/1" do
    test "returns the project" do
      project = project_fixture()
      assert Projects.get_project!(project.id).id == project.id
    end

    test "raises on missing id" do
      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project!(0)
      end
    end
  end

  describe "create_project/1" do
    test "creates with valid attrs" do
      assert {:ok, project} =
               Projects.create_project(%{
                 name: "new-project",
                 repo_url: "https://github.com/t/r.git"
               })

      assert project.name == "new-project"
      assert project.default_branch == "main"
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Projects.create_project(%{name: ""})
    end
  end

  describe "update_project/2" do
    test "updates with valid attrs" do
      project = project_fixture()
      assert {:ok, updated} = Projects.update_project(project, %{name: "renamed"})
      assert updated.name == "renamed"
    end
  end

  describe "delete_project/1" do
    test "deletes the project" do
      project = project_fixture()
      assert {:ok, _} = Projects.delete_project(project)
      assert_raise Ecto.NoResultsError, fn -> Projects.get_project!(project.id) end
    end
  end

  describe "change_project/2" do
    test "returns a changeset" do
      project = project_fixture()
      assert %Ecto.Changeset{} = Projects.change_project(project)
    end
  end

  describe "env vars" do
    test "list_env_vars(:global) returns only global vars" do
      env_var_fixture(%{key: "GLOBAL_ONE", scope: :global})

      project = project_fixture()
      env_var_fixture(%{key: "PROJ_ONE", scope: :project, project_id: project.id})

      globals = Projects.list_env_vars(:global)
      assert length(globals) == 1
      assert hd(globals).key == "GLOBAL_ONE"
    end

    test "list_env_vars(project_id) returns only project-scoped vars" do
      project = project_fixture()
      env_var_fixture(%{key: "PROJ_VAR", scope: :project, project_id: project.id})
      env_var_fixture(%{key: "GLOBAL_VAR", scope: :global})

      proj_vars = Projects.list_env_vars(project.id)
      assert length(proj_vars) == 1
      assert hd(proj_vars).key == "PROJ_VAR"
    end

    test "create_env_var/1 creates an env var" do
      assert {:ok, ev} = Projects.create_env_var(%{key: "NEW_VAR", value: "val", scope: :global})
      assert ev.key == "NEW_VAR"
    end

    test "update_env_var/2 updates an env var" do
      ev = env_var_fixture()
      assert {:ok, updated} = Projects.update_env_var(ev, %{value: "new_value"})
      assert updated.value == "new_value"
    end

    test "delete_env_var/1 deletes an env var" do
      ev = env_var_fixture()
      assert {:ok, _} = Projects.delete_env_var(ev)
    end

    test "change_env_var/2 returns a changeset" do
      ev = env_var_fixture()
      assert %Ecto.Changeset{} = Projects.change_env_var(ev)
    end
  end

  describe "resolve_env_vars/1" do
    test "merges global and project vars" do
      project = project_fixture()
      env_var_fixture(%{key: "SHARED", value: "global_val", scope: :global})
      env_var_fixture(%{key: "ONLY_GLOBAL", value: "g", scope: :global})

      env_var_fixture(%{
        key: "SHARED",
        value: "proj_val",
        scope: :project,
        project_id: project.id
      })

      resolved = Projects.resolve_env_vars(project.id) |> Map.new()

      # Project overrides global for same key
      assert resolved["SHARED"] == "proj_val"
      assert resolved["ONLY_GLOBAL"] == "g"
    end

    test "returns empty list when no env vars" do
      project = project_fixture()
      assert Projects.resolve_env_vars(project.id) == []
    end
  end

  describe "parse_dotenv/1" do
    test "parses key=value lines" do
      assert [%{key: "FOO", value: "bar"}] = Projects.parse_dotenv("FOO=bar")
    end

    test "skips comments and blank lines" do
      content = """
      # this is a comment
      FOO=bar

      # another comment
      BAZ=qux
      """

      result = Projects.parse_dotenv(content)
      assert length(result) == 2
    end

    test "strips surrounding quotes from values" do
      content = ~s(FOO="quoted value"\nBAR='single quoted')
      result = Projects.parse_dotenv(content) |> Map.new(&{&1.key, &1.value})

      assert result["FOO"] == "quoted value"
      assert result["BAR"] == "single quoted"
    end

    test "handles values containing =" do
      assert [%{key: "URL", value: "https://example.com?a=1&b=2"}] =
               Projects.parse_dotenv("URL=https://example.com?a=1&b=2")
    end

    test "skips malformed lines" do
      assert [] = Projects.parse_dotenv("no_equals_sign")
    end
  end
end

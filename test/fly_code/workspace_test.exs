defmodule FlyCode.WorkspaceTest do
  use ExUnit.Case, async: false

  alias FlyCode.Workspace

  @test_base "/tmp/fly_code_test_workspaces"

  setup do
    # Clean up test workspace dir
    File.rm_rf!(@test_base)
    File.mkdir_p!(@test_base)

    on_exit(fn ->
      File.rm_rf!(@test_base)
      File.rm_rf!("/tmp/fly_code/workspaces")
    end)

    :ok
  end

  describe "inject_env_vars/1" do
    test "sets system environment variables" do
      key = "FLYCODE_TEST_#{System.unique_integer([:positive])}"

      on_exit(fn -> System.delete_env(key) end)

      Workspace.inject_env_vars([{key, "test_value"}])
      assert System.get_env(key) == "test_value"
    end

    test "returns :ok" do
      assert :ok = Workspace.inject_env_vars([])
    end
  end

  describe "setup/3 and list_files/1" do
    setup do
      # Create a bare git repo to clone from
      bare_path = Path.join(@test_base, "bare_repo.git")
      File.mkdir_p!(bare_path)

      System.cmd("git", ["init", "--bare", "--initial-branch=main", bare_path],
        stderr_to_stdout: true
      )

      # Create a temp working repo, add a file, push to bare
      work_path = Path.join(@test_base, "work")
      System.cmd("git", ["clone", bare_path, work_path], stderr_to_stdout: true)

      System.cmd("git", ["-C", work_path, "config", "user.email", "test@test.com"],
        stderr_to_stdout: true
      )

      System.cmd("git", ["-C", work_path, "config", "user.name", "Test"], stderr_to_stdout: true)
      File.write!(Path.join(work_path, "README.md"), "# Test")
      System.cmd("git", ["-C", work_path, "add", "."], stderr_to_stdout: true)
      System.cmd("git", ["-C", work_path, "commit", "-m", "init"], stderr_to_stdout: true)
      System.cmd("git", ["-C", work_path, "push", "origin", "main"], stderr_to_stdout: true)

      File.rm_rf!(work_path)

      {:ok, bare_path: "file://#{bare_path}"}
    end

    test "clones a repo into workspace", %{bare_path: bare_path} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      assert {:ok, workspace_path} = Workspace.setup(bare_path, session_id, branch: "main")
      assert File.dir?(workspace_path)
      assert File.exists?(Path.join(workspace_path, "README.md"))
    end

    test "pulls when workspace already exists", %{bare_path: bare_path} do
      session_id = "test-session-#{System.unique_integer([:positive])}"

      {:ok, workspace_path} = Workspace.setup(bare_path, session_id, branch: "main")
      # Call setup again — should pull instead of clone
      assert {:ok, ^workspace_path} = Workspace.setup(bare_path, session_id, branch: "main")
    end

    test "list_files returns files in the repo", %{bare_path: bare_path} do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      {:ok, workspace_path} = Workspace.setup(bare_path, session_id, branch: "main")

      assert {:ok, files} = Workspace.list_files(workspace_path)
      assert "README.md" in files
    end
  end
end

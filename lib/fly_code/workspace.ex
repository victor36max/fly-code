defmodule FlyCode.Workspace do
  @moduledoc """
  Manages git workspaces on FLAME runners.
  Handles cloning, pulling, and env var injection.
  """

  require Logger

  @base_dir "/tmp/fly_code/workspaces"

  def setup(repo_url, session_id, opts \\ []) do
    configure_git_credentials()
    workspace_path = Path.join(@base_dir, session_id)

    if File.dir?(workspace_path) do
      Logger.info("Workspace exists, pulling latest: #{workspace_path}")
      git_pull(workspace_path)
      {:ok, workspace_path}
    else
      branch = Keyword.get(opts, :branch, "main")
      Logger.info("Cloning #{repo_url} (branch: #{branch}) to #{workspace_path}")
      clone(repo_url, workspace_path, branch)
    end
  end

  def run_setup_script(workspace_path, script) do
    Logger.info("Running setup script in #{workspace_path}")

    case System.cmd("sh", ["-c", script],
           cd: workspace_path,
           stderr_to_stdout: true,
           timeout: :timer.minutes(5)
         ) do
      {_output, 0} ->
        Logger.info("Setup script completed successfully")
        :ok

      {output, code} ->
        Logger.error("Setup script failed (exit #{code}): #{output}")
        {:error, output}
    end
  end

  def inject_env_vars(env_vars) do
    for {key, value} <- env_vars do
      System.put_env(key, value)
    end

    :ok
  end

  def push_branch(workspace_path, branch_name) do
    with {_, 0} <-
           System.cmd("git", ["-C", workspace_path, "checkout", "-b", branch_name],
             stderr_to_stdout: true
           ),
         {_, 0} <-
           System.cmd("git", ["-C", workspace_path, "push", "-u", "origin", branch_name],
             stderr_to_stdout: true
           ) do
      :ok
    else
      {output, code} ->
        Logger.error("Git push failed (exit #{code}): #{output}")
        {:error, output}
    end
  end

  def list_files(workspace_path) do
    case System.cmd("git", ["-C", workspace_path, "ls-tree", "-r", "--name-only", "HEAD"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.split(output, "\n", trim: true)}
      {output, _} -> {:error, output}
    end
  end

  defp clone(url, path, branch) do
    File.mkdir_p!(Path.dirname(path))

    case System.cmd("git", ["clone", "--depth", "50", "--branch", branch, url, path],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        {:ok, path}

      {output, code} ->
        Logger.error("Git clone failed (exit #{code}): #{output}")
        {:error, output}
    end
  end

  defp configure_git_credentials do
    case System.get_env("GIT_TOKEN") do
      nil ->
        :ok

      token ->
        case System.cmd(
               "git",
               [
                 "config",
                 "--global",
                 "credential.helper",
                 "!f() { echo \"username=x-access-token\npassword=#{token}\"; }; f"
               ],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          {output, code} -> Logger.warning("git config failed (exit #{code}): #{output}")
        end
    end
  end

  defp git_pull(path) do
    System.cmd("git", ["-C", path, "pull", "--ff-only"], stderr_to_stdout: true)
  end
end

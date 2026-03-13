defmodule FlyCode.Fixtures do
  @moduledoc """
  Shared test fixture factories.
  """

  alias FlyCode.Repo
  alias FlyCode.Projects.{Project, EnvVar}
  alias FlyCode.Sessions.Session

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      %Project{}
      |> Project.changeset(
        Map.merge(
          %{
            name: "test-project-#{System.unique_integer([:positive])}",
            repo_url: "https://github.com/test/repo.git"
          },
          attrs
        )
      )
      |> Repo.insert()

    project
  end

  def env_var_fixture(attrs \\ %{}) do
    {:ok, env_var} =
      %EnvVar{}
      |> EnvVar.changeset(
        Map.merge(
          %{
            key: "TEST_VAR_#{System.unique_integer([:positive])}",
            value: "test_value",
            scope: :global
          },
          attrs
        )
      )
      |> Repo.insert()

    env_var
  end

  def session_fixture(attrs \\ %{}) do
    project = Map.get_lazy(attrs, :project, fn -> project_fixture() end)

    {:ok, session} =
      %Session{}
      |> Session.changeset(
        Map.merge(
          %{
            session_id: Ecto.UUID.generate(),
            status: :active,
            branch: "main",
            project_id: project.id
          },
          Map.delete(attrs, :project)
        )
      )
      |> Repo.insert()

    session
  end
end

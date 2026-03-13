defmodule FlyCode.Projects do
  import Ecto.Query
  alias FlyCode.Repo
  alias FlyCode.Projects.{Project, EnvVar}

  def list_projects do
    Repo.all(from p in Project, order_by: [desc: p.updated_at])
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  # --- Env Vars ---

  def list_env_vars(:global) do
    Repo.all(from e in EnvVar, where: e.scope == :global, order_by: e.key)
  end

  def list_env_vars(project_id) do
    Repo.all(
      from e in EnvVar,
        where: e.project_id == ^project_id and e.scope == :project,
        order_by: e.key
    )
  end

  def create_env_var(attrs) do
    %EnvVar{}
    |> EnvVar.changeset(attrs)
    |> Repo.insert()
  end

  def update_env_var(%EnvVar{} = env_var, attrs) do
    env_var
    |> EnvVar.changeset(attrs)
    |> Repo.update()
  end

  def delete_env_var(%EnvVar{} = env_var) do
    Repo.delete(env_var)
  end

  def change_env_var(%EnvVar{} = env_var, attrs \\ %{}) do
    EnvVar.changeset(env_var, attrs)
  end

  @doc """
  Returns a MapSet of env var key names (global + project-scoped merged).
  Does not decrypt values — used for checking key presence.
  """
  def env_var_keys(project_id) do
    global_keys = Repo.all(from e in EnvVar, where: e.scope == :global, select: e.key)

    project_keys =
      Repo.all(
        from e in EnvVar,
          where: e.project_id == ^project_id and e.scope == :project,
          select: e.key
      )

    MapSet.new(global_keys ++ project_keys)
  end

  @doc """
  Resolves env vars for a project: global vars merged with project-specific overrides.
  Returns a list of `{key, decrypted_value}` tuples.
  """
  def resolve_env_vars(project_id) do
    global_vars = Repo.all(from e in EnvVar, where: e.scope == :global)

    project_vars =
      Repo.all(from e in EnvVar, where: e.project_id == ^project_id and e.scope == :project)

    global_vars
    |> Map.new(&{&1.key, &1.value})
    |> Map.merge(Map.new(project_vars, &{&1.key, &1.value}))
    |> Enum.to_list()
  end

  @doc """
  Parses a .env file string into a list of `%{key: key, value: value}` maps.
  """
  def parse_dotenv(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.flat_map(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          value = value |> String.trim() |> String.trim("\"") |> String.trim("'")
          [%{key: String.trim(key), value: value}]

        _ ->
          []
      end
    end)
  end
end

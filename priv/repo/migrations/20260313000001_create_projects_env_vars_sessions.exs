defmodule FlyCode.Repo.Migrations.CreateProjectsEnvVarsSessions do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :repo_url, :string, null: false
      add :default_branch, :string, null: false, default: "main"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name])

    create table(:env_vars) do
      add :key, :string, null: false
      add :value, :binary, null: false
      add :scope, :string, null: false, default: "project"
      add :project_id, references(:projects, on_delete: :delete_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:env_vars, [:key, :scope, :project_id])
    create index(:env_vars, [:project_id])
    create index(:env_vars, [:scope])

    create table(:sessions) do
      add :session_id, :string, null: false
      add :status, :string, null: false, default: "cloning"
      add :branch, :string
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:sessions, [:session_id])
    create index(:sessions, [:project_id])
  end
end

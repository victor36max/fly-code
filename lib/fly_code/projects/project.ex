defmodule FlyCode.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :repo_url, :string
    field :default_branch, :string, default: "main"

    has_many :env_vars, FlyCode.Projects.EnvVar
    has_many :sessions, FlyCode.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :repo_url, :default_branch])
    |> validate_required([:name, :repo_url])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name)
  end
end

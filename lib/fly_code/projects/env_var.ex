defmodule FlyCode.Projects.EnvVar do
  use Ecto.Schema
  import Ecto.Changeset

  schema "env_vars" do
    field :key, :string
    field :value, FlyCode.Encrypted.Binary
    field :scope, Ecto.Enum, values: [:global, :project]

    belongs_to :project, FlyCode.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(env_var, attrs) do
    env_var
    |> cast(attrs, [:key, :value, :scope, :project_id])
    |> validate_required([:key, :value, :scope])
    |> validate_format(:key, ~r/^[A-Za-z_][A-Za-z0-9_]*$/,
      message: "must be a valid env var name"
    )
    |> unique_constraint([:key, :scope, :project_id])
  end
end

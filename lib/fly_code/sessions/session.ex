defmodule FlyCode.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :session_id, :string
    field :status, Ecto.Enum, values: [:cloning, :active, :idle, :shutdown]
    field :backend, Ecto.Enum, values: [:claude_code, :opencode]
    field :branch, :string

    belongs_to :project, FlyCode.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:session_id, :status, :backend, :branch, :project_id])
    |> validate_required([:session_id, :status, :project_id])
    |> unique_constraint(:session_id)
  end
end

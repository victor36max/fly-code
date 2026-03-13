defmodule FlyCode.Repo.Migrations.AddBackendToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :backend, :string, null: false, default: "claude_code"
    end
  end
end

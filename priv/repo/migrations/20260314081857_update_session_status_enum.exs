defmodule FlyCode.Repo.Migrations.UpdateSessionStatusEnum do
  use Ecto.Migration

  def up do
    # Status is stored as a string column, not a Postgres enum type.
    # Ecto.Enum validates values at the application level.
    # Migrate existing rows to new status names.
    execute "UPDATE sessions SET status = 'completed' WHERE status = 'idle'"
    execute "UPDATE sessions SET status = 'setup_script' WHERE status = 'setup'"
  end

  def down do
    execute "UPDATE sessions SET status = 'idle' WHERE status = 'completed'"
    execute "UPDATE sessions SET status = 'setup' WHERE status = 'setup_script'"
    execute "UPDATE sessions SET status = 'cloning' WHERE status = 'spawning'"
    execute "UPDATE sessions SET status = 'cloning' WHERE status = 'spawning_agent'"
    execute "UPDATE sessions SET status = 'shutdown' WHERE status = 'failed'"
  end
end

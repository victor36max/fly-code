defmodule FlyCode.Repo.Migrations.AddSetupScriptToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :setup_script, :text
    end
  end
end

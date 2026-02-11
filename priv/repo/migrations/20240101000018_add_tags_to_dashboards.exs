defmodule SwitchTelemetry.Repo.Migrations.AddTagsToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :tags, {:array, :string}, default: []
    end
  end
end

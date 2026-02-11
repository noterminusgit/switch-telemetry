defmodule SwitchTelemetry.Repo.Migrations.CreateDashboards do
  use Ecto.Migration

  def change do
    create table(:dashboards, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :layout, :string, default: "grid"
      add :refresh_interval_ms, :integer, default: 5_000
      add :is_public, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:dashboards, [:name])
  end
end

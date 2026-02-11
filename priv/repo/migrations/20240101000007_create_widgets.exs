defmodule SwitchTelemetry.Repo.Migrations.CreateWidgets do
  use Ecto.Migration

  def change do
    create table(:widgets, primary_key: false) do
      add :id, :string, primary_key: true

      add :dashboard_id, references(:dashboards, type: :string, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :chart_type, :string, null: false
      add :position, :map, default: %{x: 0, y: 0, w: 6, h: 4}
      add :time_range, :map, default: %{type: "relative", duration: "1h"}
      add :queries, {:array, :map}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create index(:widgets, [:dashboard_id])
  end
end

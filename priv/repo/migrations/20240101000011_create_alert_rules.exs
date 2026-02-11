defmodule SwitchTelemetry.Repo.Migrations.CreateAlertRules do
  use Ecto.Migration

  def change do
    create table(:alert_rules, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :device_id, references(:devices, type: :string, on_delete: :delete_all)
      add :path, :string, null: false
      add :condition, :string, null: false
      add :threshold, :float
      add :duration_seconds, :integer, null: false, default: 60
      add :cooldown_seconds, :integer, null: false, default: 300
      add :severity, :string, null: false, default: "warning"
      add :enabled, :boolean, null: false, default: true
      add :state, :string, null: false, default: "ok"
      add :last_fired_at, :utc_datetime_usec
      add :last_resolved_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:alert_rules, [:device_id])
    create index(:alert_rules, [:enabled, :state])
    create unique_index(:alert_rules, [:name])
  end
end

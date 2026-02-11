defmodule SwitchTelemetry.Repo.Migrations.CreateAlertEvents do
  use Ecto.Migration

  def change do
    create table(:alert_events, primary_key: false) do
      add :id, :string, primary_key: true
      add :alert_rule_id, references(:alert_rules, type: :string, on_delete: :delete_all),
        null: false
      add :device_id, :string
      add :status, :string, null: false
      add :value, :float
      add :message, :string
      add :metadata, :map, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:alert_events, [:alert_rule_id])
    create index(:alert_events, [:device_id, :inserted_at])
    create index(:alert_events, [:inserted_at])
  end
end

defmodule SwitchTelemetry.Repo.Migrations.CreateAlertChannelBindings do
  use Ecto.Migration

  def change do
    create table(:alert_channel_bindings, primary_key: false) do
      add :id, :string, primary_key: true
      add :alert_rule_id, references(:alert_rules, type: :string, on_delete: :delete_all),
        null: false
      add :notification_channel_id,
        references(:notification_channels, type: :string, on_delete: :delete_all),
        null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:alert_channel_bindings, [:alert_rule_id, :notification_channel_id])
  end
end

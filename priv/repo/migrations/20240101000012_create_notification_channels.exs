defmodule SwitchTelemetry.Repo.Migrations.CreateNotificationChannels do
  use Ecto.Migration

  def change do
    create table(:notification_channels, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :config, :map, null: false, default: %{}
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_channels, [:name])
  end
end

defmodule SwitchTelemetry.Repo.Migrations.AddSecureMode do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :secure_mode, :boolean, default: false, null: false
    end

    create table(:security_settings) do
      add :require_secure_gnmi, :boolean, default: false, null: false
      add :require_credentials, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end

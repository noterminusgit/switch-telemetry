defmodule SwitchTelemetry.Repo.Migrations.CreateSmtpSettings do
  use Ecto.Migration

  def change do
    create table(:smtp_settings) do
      add :relay, :string
      add :port, :integer, default: 587
      add :username, :string
      add :password, :binary
      add :from_email, :string, default: "noreply@switch-telemetry.local"
      add :from_name, :string, default: "Switch Telemetry"
      add :tls, :boolean, default: true
      add :enabled, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end

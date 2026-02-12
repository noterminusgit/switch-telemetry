defmodule SwitchTelemetry.Repo.Migrations.AddRetentionPolicies do
  use Ecto.Migration

  # TimescaleDB retention policies removed — retention now configured per
  # InfluxDB bucket at creation time. See priv/influxdb/setup.sh.

  def up, do: :ok
  def down, do: :ok
end

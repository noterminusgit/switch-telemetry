defmodule SwitchTelemetry.Repo.Migrations.CompressMetrics do
  use Ecto.Migration

  # Originally set up compression on the metrics hypertable. Now a no-op
  # since metrics have been migrated to InfluxDB.

  # TimescaleDB compression removed — metrics now stored in InfluxDB.

  def up, do: :ok
  def down, do: :ok
end

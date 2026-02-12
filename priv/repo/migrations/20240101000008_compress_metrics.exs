defmodule SwitchTelemetry.Repo.Migrations.CompressMetrics do
  use Ecto.Migration

  # Originally set up compression on the metrics hypertable. Now a no-op
  # since metrics have been migrated to InfluxDB.

  def up do
    if timescaledb_community?() do
      execute "ALTER TABLE metrics SET (timescaledb.compress, timescaledb.compress_segmentby = 'device_id, path')"
      execute "SELECT add_compression_policy('metrics', INTERVAL '7 days')"
    end
  end

  def down do
    if timescaledb_community?() do
      execute "SELECT remove_compression_policy('metrics')"
      execute "ALTER TABLE metrics SET (timescaledb.compress = false)"
    end
  end

  defp timescaledb_community? do
    %{rows: [[license]]} =
      repo().query!("SHOW timescaledb.license")

    license == "timescale"
  end
end

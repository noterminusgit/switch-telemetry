defmodule SwitchTelemetry.Repo.Migrations.CompressMetrics do
  use Ecto.Migration
  import Timescale.Migration

  def up do
    if timescaledb_community?() do
      enable_hypertable_compression(:metrics, segment_by: "device_id, path")
      add_compression_policy(:metrics, "7 days")
    end
  end

  def down do
    if timescaledb_community?() do
      remove_compression_policy(:metrics)
      disable_hypertable_compression(:metrics)
    end
  end

  defp timescaledb_community? do
    %{rows: [[license]]} =
      repo().query!("SHOW timescaledb.license")

    license == "timescale"
  end
end

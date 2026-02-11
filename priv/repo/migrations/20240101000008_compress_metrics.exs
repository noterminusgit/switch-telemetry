defmodule SwitchTelemetry.Repo.Migrations.CompressMetrics do
  use Ecto.Migration
  import Timescale.Migration

  def up do
    enable_hypertable_compression(:metrics, segment_by: "device_id, path")
    add_compression_policy(:metrics, "7 days")
  end

  def down do
    remove_compression_policy(:metrics)
    disable_hypertable_compression(:metrics)
  end
end

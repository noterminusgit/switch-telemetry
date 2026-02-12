defmodule SwitchTelemetry.Repo.Migrations.CreateMetricAggregates do
  use Ecto.Migration

  # TimescaleDB continuous aggregates removed — downsampling now handled
  # by InfluxDB Flux tasks. See priv/influxdb/tasks/.

  def up, do: :ok
  def down, do: :ok
end

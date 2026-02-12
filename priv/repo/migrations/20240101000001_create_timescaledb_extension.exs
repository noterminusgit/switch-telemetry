defmodule SwitchTelemetry.Repo.Migrations.CreateTimescaledbExtension do
  use Ecto.Migration

  # Originally created TimescaleDB extension. Now a no-op since TimescaleDB
  # has been replaced by InfluxDB. The extension is dropped in migration
  # 20260212000001_remove_timescaledb.exs.

  def up do
    # TimescaleDB replaced by InfluxDB v2. Extension dropped in migration
    # 20260212000001_remove_timescaledb.exs.
    :ok
  end

  def down do
    :ok
  end
end

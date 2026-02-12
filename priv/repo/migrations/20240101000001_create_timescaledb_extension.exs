defmodule SwitchTelemetry.Repo.Migrations.CreateTimescaledbExtension do
  use Ecto.Migration

  # Originally created TimescaleDB extension. Now a no-op since TimescaleDB
  # has been replaced by InfluxDB. The extension is dropped in migration
  # 20260212000001_remove_timescaledb.exs.

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS timescaledb CASCADE"
  end
end

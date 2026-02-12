defmodule SwitchTelemetry.Repo.Migrations.RemoveTimescaledb do
  use Ecto.Migration

  def up do
    # Drop retention policies (if they exist)
    execute "SELECT remove_retention_policy('metrics', if_exists => true)"

    # Drop continuous aggregates
    execute "DROP MATERIALIZED VIEW IF EXISTS metrics_1h CASCADE"
    execute "DROP MATERIALIZED VIEW IF EXISTS metrics_5m CASCADE"

    # Drop the metrics hypertable
    drop_if_exists table(:metrics)

    # Drop TimescaleDB extension
    execute "DROP EXTENSION IF EXISTS timescaledb CASCADE"
  end

  def down do
    # Re-creating TimescaleDB from scratch is not supported in a down migration.
    # Restore from backup instead.
    raise Ecto.MigrationError,
      message: "Cannot reverse TimescaleDB removal. Restore from backup."
  end
end

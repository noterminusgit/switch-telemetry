defmodule SwitchTelemetry.Repo.Migrations.RemoveTimescaledb do
  use Ecto.Migration

  def up do
    # Drop continuous aggregates (standard SQL, safe without TimescaleDB)
    execute "DROP MATERIALIZED VIEW IF EXISTS metrics_1h CASCADE"
    execute "DROP MATERIALIZED VIEW IF EXISTS metrics_5m CASCADE"

    # Drop the metrics table
    drop_if_exists table(:metrics)

    # Drop TimescaleDB extension (no-op if not installed)
    execute "DROP EXTENSION IF EXISTS timescaledb CASCADE"
  end

  def down do
    # Re-creating TimescaleDB from scratch is not supported in a down migration.
    # Restore from backup instead.
    raise Ecto.MigrationError,
      message: "Cannot reverse TimescaleDB removal. Restore from backup."
  end
end

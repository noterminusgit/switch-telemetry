defmodule SwitchTelemetry.Repo.Migrations.CreateMetricAggregates do
  use Ecto.Migration

  def up do
    execute """
    CREATE MATERIALIZED VIEW metrics_5m
    WITH (timescaledb.continuous) AS
      SELECT
        time_bucket('5 minutes', time) AS bucket,
        device_id,
        path,
        avg(value_float) AS avg_value,
        max(value_float) AS max_value,
        min(value_float) AS min_value,
        count(*) AS sample_count
      FROM metrics
      WHERE value_float IS NOT NULL
      GROUP BY bucket, device_id, path
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy('metrics_5m',
      start_offset => INTERVAL '30 minutes',
      end_offset => INTERVAL '5 minutes',
      schedule_interval => INTERVAL '5 minutes')
    """

    execute """
    CREATE MATERIALIZED VIEW metrics_1h
    WITH (timescaledb.continuous) AS
      SELECT
        time_bucket('1 hour', time) AS bucket,
        device_id,
        path,
        avg(value_float) AS avg_value,
        max(value_float) AS max_value,
        min(value_float) AS min_value,
        count(*) AS sample_count
      FROM metrics
      WHERE value_float IS NOT NULL
      GROUP BY bucket, device_id, path
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy('metrics_1h',
      start_offset => INTERVAL '3 hours',
      end_offset => INTERVAL '1 hour',
      schedule_interval => INTERVAL '1 hour')
    """
  end

  def down do
    execute "DROP MATERIALIZED VIEW IF EXISTS metrics_1h CASCADE"
    execute "DROP MATERIALIZED VIEW IF EXISTS metrics_5m CASCADE"
  end
end

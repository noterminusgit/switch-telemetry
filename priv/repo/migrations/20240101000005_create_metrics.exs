defmodule SwitchTelemetry.Repo.Migrations.CreateMetrics do
  use Ecto.Migration

  # Originally created the metrics hypertable. Now a no-op since metrics
  # have been migrated to InfluxDB. The table is dropped in migration
  # 20260212000001_remove_timescaledb.exs.

  def up do
    create table(:metrics, primary_key: false) do
      add :time, :utc_datetime_usec, null: false
      add :device_id, :string, null: false
      add :path, :string, null: false
      add :source, :string, null: false, default: "gnmi"
      add :tags, :map, default: %{}
      add :value_float, :float
      add :value_int, :bigint
      add :value_str, :string
    end

    flush()
    execute "SELECT create_hypertable('metrics', 'time')"

    create index(:metrics, [:device_id, :time])
    create index(:metrics, [:device_id, :path, :time])
  end

  def down do
    drop table(:metrics)
  end
end

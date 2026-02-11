defmodule SwitchTelemetry.Repo.Migrations.CreateMetrics do
  use Ecto.Migration
  import Timescale.Migration

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

    # Must flush between create table and create_hypertable
    flush()
    create_hypertable(:metrics, :time)

    # Composite indexes -- time column must be included for hypertable performance
    create index(:metrics, [:device_id, :time])
    create index(:metrics, [:device_id, :path, :time])
  end

  def down do
    drop table(:metrics)
  end
end

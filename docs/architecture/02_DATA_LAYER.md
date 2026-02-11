# 02: Data Layer

## TimescaleDB Setup

TimescaleDB is a PostgreSQL extension. It uses standard Ecto with the `timescale` hex package for migration helpers and hyperfunctions.

### Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:ecto_sql, "~> 3.12"},
    {:postgrex, ">= 0.0.0"},
    {:timescale, "~> 0.1.0"}   # hypertable migrations + hyperfunctions
  ]
end
```

## Migrations

### Enable TimescaleDB Extension

```elixir
defmodule SwitchTelemetry.Repo.Migrations.CreateTimescaleExtension do
  use Ecto.Migration
  import Timescale.Migration

  def up do
    create_timescaledb_extension()
  end

  def down do
    drop_timescaledb_extension()
  end
end
```

### Devices Table

```elixir
defmodule SwitchTelemetry.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :string, primary_key: true        # ULID with "dev_" prefix
      add :hostname, :string, null: false
      add :ip_address, :string, null: false
      add :platform, :string, null: false
      add :transport, :string, null: false, default: "gnmi"
      add :gnmi_port, :integer, default: 57400
      add :netconf_port, :integer, default: 830
      add :credentials_id, references(:credentials, type: :string)
      add :tags, :map, default: %{}
      add :collection_interval_ms, :integer, default: 30_000
      add :status, :string, default: "active"
      add :assigned_collector, :string              # node name
      add :collector_heartbeat, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:devices, [:hostname])
    create unique_index(:devices, [:ip_address])
    create index(:devices, [:status])
    create index(:devices, [:assigned_collector])
    create index(:devices, [:platform])
  end
end
```

### Metrics Hypertable

```elixir
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

    # Convert to hypertable -- MUST flush after create table
    flush()
    create_hypertable(:metrics, :time)

    # Composite indexes -- time column must be included for ingest performance
    create index(:metrics, [:device_id, :time])
    create index(:metrics, [:device_id, :path, :time])
  end

  def down do
    drop table(:metrics)
  end
end
```

### Compression Policy

```elixir
defmodule SwitchTelemetry.Repo.Migrations.CompressMetrics do
  use Ecto.Migration
  import Timescale.Migration

  def up do
    # Compress by device_id so queries for a single device are efficient
    enable_hypertable_compression(:metrics, segment_by: "device_id, path")

    # Compress chunks older than 7 days
    add_compression_policy(:metrics, "7 days")
  end

  def down do
    remove_compression_policy(:metrics)
    disable_hypertable_compression(:metrics)
  end
end
```

### Continuous Aggregates

```elixir
defmodule SwitchTelemetry.Repo.Migrations.CreateMetricAggregates do
  use Ecto.Migration

  def up do
    # 5-minute rollup
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

    # Refresh policy: refresh every 5 minutes, covering last 30 minutes
    execute """
    SELECT add_continuous_aggregate_policy('metrics_5m',
      start_offset => INTERVAL '30 minutes',
      end_offset => INTERVAL '5 minutes',
      schedule_interval => INTERVAL '5 minutes')
    """

    # 1-hour rollup
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
```

### Data Retention Policy

```elixir
defmodule SwitchTelemetry.Repo.Migrations.AddRetentionPolicies do
  use Ecto.Migration

  def up do
    # Keep raw metrics for 30 days
    execute "SELECT add_retention_policy('metrics', INTERVAL '30 days')"

    # Keep 5-minute aggregates for 6 months
    execute "SELECT add_retention_policy('metrics_5m', INTERVAL '180 days')"

    # Keep 1-hour aggregates for 2 years
    execute "SELECT add_retention_policy('metrics_1h', INTERVAL '730 days')"
  end

  def down do
    execute "SELECT remove_retention_policy('metrics')"
    execute "SELECT remove_retention_policy('metrics_5m')"
    execute "SELECT remove_retention_policy('metrics_1h')"
  end
end
```

## Ecto Schemas

### Metric Schema

```elixir
defmodule SwitchTelemetry.Metrics.Metric do
  use Ecto.Schema

  @primary_key false
  schema "metrics" do
    field :time, :utc_datetime_usec
    field :device_id, :string
    field :path, :string
    field :source, :string
    field :tags, :map, default: %{}
    field :value_float, :float
    field :value_int, :integer
    field :value_str, :string
  end
end
```

## Query Patterns

### Real-Time: Latest Metrics for a Device

```elixir
import Ecto.Query
import Timescale.Hyperfunctions

def get_latest(device_id, opts \\ []) do
  limit = Keyword.get(opts, :limit, 100)

  from(m in "metrics",
    where: m.device_id == ^device_id,
    where: m.time > ago(5, "minute"),
    order_by: [desc: m.time],
    limit: ^limit,
    select: %{
      time: m.time,
      path: m.path,
      value: m.value_float
    }
  )
  |> Repo.all()
end
```

### Historical: Time-Bucketed Aggregation

```elixir
def get_time_series(device_id, path, bucket_size, time_range) do
  from(m in "metrics",
    where: m.device_id == ^device_id,
    where: m.path == ^path,
    where: m.time >= ^time_range.start and m.time <= ^time_range.end,
    group_by: selected_as(:bucket),
    order_by: selected_as(:bucket),
    select: %{
      bucket: selected_as(time_bucket(m.time, ^bucket_size), :bucket),
      avg: avg(m.value_float),
      max: max(m.value_float),
      min: min(m.value_float),
      count: count(m.id)
    }
  )
  |> Repo.all()
end
```

### Rate Calculation (for counters like octets)

```elixir
def get_rate(device_id, path, bucket_size, time_range) do
  # Use a subquery with lag() to calculate rate of change
  Repo.query!("""
    SELECT
      time_bucket($1, time) AS bucket,
      (max(value_int) - min(value_int)) / EXTRACT(EPOCH FROM $1::interval) AS rate_per_sec
    FROM metrics
    WHERE device_id = $2
      AND path = $3
      AND time >= $4
      AND time <= $5
      AND value_int IS NOT NULL
    GROUP BY bucket
    ORDER BY bucket
  """, [bucket_size, device_id, path, time_range.start, time_range.end])
end
```

### Batch Insert (used by collectors)

```elixir
def insert_batch(metrics) when is_list(metrics) do
  # Use Repo.insert_all for high-throughput batch inserts
  entries =
    Enum.map(metrics, fn m ->
      %{
        time: m.time,
        device_id: m.device_id,
        path: m.path,
        source: to_string(m.source),
        tags: m.tags || %{},
        value_float: m.value_float,
        value_int: m.value_int,
        value_str: m.value_str
      }
    end)

  # insert_all with on_conflict: :nothing for idempotency
  Repo.insert_all("metrics", entries,
    on_conflict: :nothing,
    conflict_target: [:time, :device_id, :path]
  )
end
```

## Indexing Strategy

| Index | Columns | Purpose |
|---|---|---|
| Hypertable partition | `time` (automatic) | TimescaleDB chunks by time |
| Composite B-tree | `(device_id, time)` | "Show me all metrics for device X in the last hour" |
| Composite B-tree | `(device_id, path, time)` | "Show me interface counters for device X, path Y" |

**Why no index without `time`?** TimescaleDB documentation warns that indexes without the time column cause very slow ingest speeds because they can't leverage chunk-level index pruning.

## Performance Targets

| Metric | Target |
|---|---|
| Ingestion rate | 100,000+ metrics/second across all collectors |
| Single device query (last 5 min) | < 10ms |
| Time-bucketed query (1 hour, 1min buckets) | < 50ms |
| Time-bucketed query (7 days, 1h buckets) | < 200ms (via continuous aggregate) |
| Compression ratio | 10:1+ for metrics older than 7 days |
| Raw data retention | 30 days |
| 5-minute aggregate retention | 6 months |
| 1-hour aggregate retention | 2 years |

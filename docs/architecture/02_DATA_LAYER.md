# 02: Data Layer

## Overview

Switch Telemetry uses a dual-database architecture:
- **InfluxDB v2** for time-series metrics (ingestion, aggregation, retention)
- **PostgreSQL** for relational data (devices, dashboards, users, alerts, Oban jobs)

## InfluxDB v2 Setup

### Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:instream, "~> 2.2"},   # InfluxDB v2 client (line protocol + Flux queries)
  ]
end
```

### Connection Module

```elixir
defmodule SwitchTelemetry.InfluxDB do
  use Instream.Connection, otp_app: :switch_telemetry
end
```

### Configuration

```elixir
# config/config.exs
config :switch_telemetry, SwitchTelemetry.InfluxDB,
  host: "http://localhost",
  port: 8086,
  token: "dev-token",
  bucket: "metrics_raw",
  org: "switch-telemetry",
  version: :v2
```

Production config reads from environment variables: `INFLUXDB_HOST`, `INFLUXDB_PORT`, `INFLUXDB_TOKEN`, `INFLUXDB_ORG`, `INFLUXDB_BUCKET`.

## Buckets and Retention

| Bucket | Retention | Purpose |
|--------|-----------|---------|
| `metrics_raw` | 30 days | Raw ingested data points |
| `metrics_5m` | 180 days | 5-minute aggregated rollups |
| `metrics_1h` | 730 days | 1-hour aggregated rollups |
| `metrics_test` | None | Test environment bucket |

Buckets are created via `priv/influxdb/setup.sh`.

## Downsampling

InfluxDB Flux tasks handle automatic downsampling:
- **downsample_5m**: Runs every 5 minutes, aggregates raw data (mean, max, min, count) into `metrics_5m`
- **downsample_1h**: Runs every hour, aggregates raw data into `metrics_1h`

Tasks are deployed via `priv/influxdb/deploy_tasks.sh`.

## Metrics Backend Abstraction

A `SwitchTelemetry.Metrics.Backend` behaviour defines the contract:

```elixir
@callback insert_batch([metric()]) :: {non_neg_integer(), nil}
@callback get_latest(String.t(), keyword()) :: [map()]
@callback query(String.t(), String.t(), time_range()) :: [map()]
@callback query_raw(String.t(), String.t(), String.t(), time_range()) :: [map()]
@callback query_rate(String.t(), String.t(), String.t(), time_range()) :: [map()]
```

The active backend is configured via:
```elixir
config :switch_telemetry, :metrics_backend, SwitchTelemetry.Metrics.InfluxBackend
```

## Data Model

Metrics are written as InfluxDB line protocol points:
- **Measurement**: `metrics`
- **Tags**: `device_id`, `path`, `source`
- **Fields**: `value_float`, `value_int`, `value_str`
- **Timestamp**: nanosecond precision

## Query Patterns

### Real-Time: Latest Metrics for a Device

```elixir
Metrics.get_latest(device_id, limit: 100, minutes: 5)
```

Uses Flux: `from(bucket) |> range |> filter |> pivot |> sort(desc) |> limit`

### Historical: Time-Bucketed Aggregation

```elixir
QueryRouter.query(device_id, path, time_range)
```

Routes automatically:
- <= 1 hour: raw bucket with `aggregateWindow(every: 10s)`
- 1-24 hours: `metrics_5m` downsampled bucket
- > 24 hours: `metrics_1h` downsampled bucket

### Rate Calculation (for counters like octets)

```elixir
QueryRouter.query_rate(device_id, path, bucket_size, time_range)
```

Uses Flux join of max/min aggregateWindow results to compute `(max - min) / interval_seconds`.

### Batch Insert (used by collectors)

```elixir
Metrics.insert_batch([%{time: dt, device_id: "dev_1", path: "/cpu", source: :gnmi, value_float: 42.5}])
```

Converts to line protocol points and writes via Instream.

## Performance Targets

| Metric | Target |
|---|---|
| Ingestion rate | 100,000+ metrics/second across all collectors |
| Single device query (last 5 min) | < 10ms |
| Time-bucketed query (1 hour, 10s buckets) | < 50ms |
| Time-bucketed query (7 days, 1h buckets) | < 200ms (via downsampled bucket) |
| Raw data retention | 30 days |
| 5-minute aggregate retention | 6 months |
| 1-hour aggregate retention | 2 years |

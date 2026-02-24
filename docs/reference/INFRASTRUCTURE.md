# Infrastructure Reference

## Tech Stack

| Layer | Package | Version |
|-------|---------|---------|
| Web framework | `phoenix` + `bandit` | ~> 1.7 / ~> 1.0 |
| LiveView | `phoenix_live_view` | ~> 1.0 |
| PostgreSQL | `ecto_sql` + `postgrex` | ~> 3.12 |
| InfluxDB v2 | `instream` | ~> 2.2 |
| gRPC | `grpc` + `protobuf` | ~> 0.9 / ~> 0.14 |
| SSH/NETCONF | Erlang `:ssh` + `sweet_xml` | ~> 0.7 |
| Charts | `vega_lite` + `tucan` | ~> 0.1 / ~> 0.5 |
| Distribution | `horde` + `libcluster` | ~> 0.9 / ~> 3.4 |
| Jobs | `oban` | ~> 2.17 |
| Encryption | `cloak_ecto` + `bcrypt_elixir` | ~> 1.3 / ~> 3.0 |
| HTTP/Email | `finch` + `swoosh` | ~> 0.18 / ~> 1.16 |

## InfluxDB & Metrics

**Buckets**: `metrics_raw` (30d retention), `metrics_5m` (180d), `metrics_1h` (730d), `metrics_test` (no retention).

**Write format**:
```elixir
%{measurement: "metrics", tags: %{device_id: id, path: path, source: "gnmi"},
  fields: %{value_float: 42.0}, timestamp: System.os_time(:nanosecond)}
```

**Row maps**: String keys — `"_time"`, `"_value"`, `"_field"`, `"device_id"`, `"path"`, `"result"`. Timestamps are nanosecond integers (not ISO8601).

**Multi-yield gotcha**: `InfluxDB.query/1` returns list-of-lists for multi-yield Flux. **Must `List.flatten/1`** before processing.

**QueryRouter bucket selection**:
- ≤ 1 hour → `metrics_raw` (10s aggregation windows)
- 1–24 hours → `metrics_5m`
- \> 24 hours → `metrics_1h`

**`query_by_prefix/3`**: Converts subscription paths to Flux regex allowing optional `[key=val]` selectors between segments. E.g., `/interfaces/interface/state/counters` matches `/interfaces/interface[name=Gi0/0/0]/state/counters/in-octets`. Returns `[%{path: String.t(), data: [%{bucket: DateTime, avg_value: float}]}]`.

**Env vars**: `INFLUXDB_HOST` (localhost), `INFLUXDB_PORT` (8086), `INFLUXDB_SCHEME` (http), `INFLUXDB_TOKEN`, `INFLUXDB_ORG`, `INFLUXDB_BUCKET`.

**Setup scripts**: `priv/influxdb/setup.sh` (creates buckets), `priv/influxdb/deploy_tasks.sh`. Downsampling tasks in `priv/influxdb/tasks/`.

## PubSub Topics

| Topic | Message | Publisher | Subscriber |
|-------|---------|-----------|------------|
| `"device:#{id}"` | `{:gnmi_metrics, id, metrics}` | GnmiSession | DeviceLive.Show, DashboardLive.Show |
| `"device:#{id}"` | `{:netconf_metrics, id, metrics}` | NetconfSession | DeviceLive.Show, DashboardLive.Show |
| `"stream_monitor"` | `{:stream_update, status}` | StreamMonitor | StreamLive.Monitor |
| `"stream_monitor"` | `{:streams_full, [statuses]}` | StreamMonitor | StreamLive.Monitor |
| `"alerts"` | `{:alert_event, event}` | AlertEvaluator | AlertLive.Index |
| `"alerts:#{device_id}"` | `{:alert_event, event}` | AlertEvaluator | (device-scoped) |

## Oban Workers & Queues

| Worker | Queue | Schedule | Max Attempts | Description |
|--------|-------|----------|-------------|-------------|
| AlertEvaluator | `alerts` | `* * * * *` (every minute) | 1 | Evaluate all enabled alert rules |
| AlertNotifier | `notifications` | On-demand | 5 | Deliver webhook/Slack/email notifications |
| AlertEventPruner | `maintenance` | `0 3 * * *` (daily 3am) | 1 | Prune events older than 30 days |
| DeviceDiscovery | `discovery` | On-demand | 3 | Assign devices to collectors via HashRing |
| StaleSessionCleanup | `maintenance` | On-demand | 3 | Clean Horde sessions from dead nodes |

**Queue config**: `default: 10, discovery: 2, maintenance: 1, notifications: 5, alerts: 1`.

**Note**: Oban only starts on collector nodes. Jobs can be enqueued from any node (via PostgreSQL) but only process on collectors.

## Charting

**TelemetryChart** (`SwitchTelemetryWeb.Components.TelemetryChart`): LiveComponent that builds VegaLite specs and pushes to browser via `VegaLiteHook`.

**Assigns**: `series` (list), `chart_type` (atom), `width`, `height`, `responsive` (boolean), `title` (optional).

**Series format**: `[%{label: "name", data: [%{time: DateTime.t(), value: float()}]}]`.

**Chart types**: `:line`, `:area`, `:bar`, `:points` (VegaLite mark: `"point"`). Falls back to `:line`.

**JS hooks**: `VegaLite` in `assets/js/hooks/vega_lite.js`, `DashboardGrid` in `assets/js/hooks/dashboard_grid.js`.

**npm deps**: `vega`, `vega-lite`, `vega-embed`.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NODE_ROLE` | `"collector"`, `"web"`, or `"both"` | `"both"` |
| `DATABASE_URL` | PostgreSQL connection string | — |
| `INFLUXDB_HOST` | InfluxDB hostname | `"localhost"` |
| `INFLUXDB_PORT` | InfluxDB port | `8086` |
| `INFLUXDB_SCHEME` | InfluxDB protocol | `"http"` |
| `INFLUXDB_TOKEN` | InfluxDB auth token | — |
| `INFLUXDB_ORG` | InfluxDB organization | — |
| `INFLUXDB_BUCKET` | InfluxDB bucket name | — |
| `CLOAK_KEY` | Base64-encoded AES-256 key | — |
| `SECRET_KEY_BASE` | Phoenix secret | — |
| `PHX_HOST` | Public hostname | `"localhost"` |

See also: `docs/security/ENV_VARS.md` for production hardening.

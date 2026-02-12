# ADR-005: Migration from TimescaleDB to InfluxDB v2

**Status:** Accepted
**Date:** 2026-02-12
**Deciders:** Engineering team
**Context:** TimescaleDB license restrictions blocking production features

## Context

Switch Telemetry originally used TimescaleDB (a PostgreSQL extension) for all time-series metrics storage. During production hardening (Phase 7-8), we discovered that key TimescaleDB features required for operational maturity are gated behind the TimescaleDB Community (non-Apache) license:

- **Compression policies** -- needed to manage storage growth at scale
- **Continuous aggregates** -- needed for performant dashboard queries over long time ranges
- **Advanced retention policies** -- needed for automatic data lifecycle management

The Apache-only license available on standard self-hosted installations does not include these features. Migrations referencing these features were failing, blocking CI and production deployment.

## Decision

Migrate all time-series metrics from TimescaleDB to **InfluxDB v2** while retaining PostgreSQL for relational data.

## Rationale

### Why migrate at all?

- TimescaleDB Community license is not Apache 2.0; it restricts redistribution and cloud offerings
- Self-hosted installations default to Apache-only, missing critical features
- Upgrading to the Community license adds operational complexity and legal review
- The project values fully open-source dependencies

### Why InfluxDB v2?

1. **Fully open source** -- InfluxDB OSS v2 includes all features (retention, Flux tasks, downsampling) under the MIT license
2. **Purpose-built** -- Native time-series storage engine (TSM) optimized for write-heavy workloads
3. **Mature Elixir client** -- `instream` hex package (~2.2) provides complete InfluxDB v2 support
4. **Built-in downsampling** -- Flux tasks replace continuous aggregates natively
5. **Bucket retention** -- Per-bucket retention policies configured at creation time
6. **Line protocol** -- High-throughput write format with nanosecond precision

## Alternatives Considered

### Alternative 1: Upgrade TimescaleDB License

**Pros:**
- Zero code changes
- Keep existing SQL-based queries

**Cons:**
- Non-Apache license with usage restrictions
- Ongoing license management burden
- Dependency on TimescaleDB Inc. licensing decisions

**Why Rejected:** Adds operational and legal complexity without technical benefit. The license could change again in the future.

### Alternative 2: ClickHouse

**Pros:**
- Excellent compression and query performance
- SQL-like query language (familiar)
- Column-oriented storage ideal for time-series

**Cons:**
- No mature Elixir client library
- Heavier operational footprint (Java-based)
- Overkill for current scale targets (5k devices, 100k metrics/sec)

**Why Rejected:** No production-ready Elixir client. Would require building and maintaining a custom HTTP/native client.

### Alternative 3: QuestDB

**Pros:**
- PostgreSQL wire protocol compatibility
- Could potentially work with existing Ecto queries
- High performance time-series engine

**Cons:**
- Smaller community and ecosystem
- No Elixir client library
- PostgreSQL compatibility is partial (not full Ecto support)

**Why Rejected:** Insufficient Elixir ecosystem support. Community too small for production reliance.

## Implementation

### Architecture Change

```
BEFORE:  Collectors → PostgreSQL/TimescaleDB (metrics + relational)
AFTER:   Collectors → InfluxDB v2 (metrics only)
                    → PostgreSQL (relational only, no extension)
```

### Backend Abstraction

A `SwitchTelemetry.Metrics.Backend` behaviour was introduced to decouple metrics storage from consumers:

```elixir
@callback insert_batch(list(map())) :: {non_neg_integer(), nil}
@callback get_latest(String.t(), keyword()) :: list(map())
@callback query(String.t(), String.t(), map()) :: list(map())
@callback query_raw(String.t(), String.t(), String.t(), map()) :: list(map())
@callback query_rate(String.t(), String.t(), String.t(), map()) :: list(map())
```

The `InfluxBackend` module implements this behaviour using Flux queries. The active backend is configured via `Application.get_env(:switch_telemetry, :metrics_backend)`.

### InfluxDB Bucket Structure

| Bucket | Retention | Purpose |
|--------|-----------|---------|
| `metrics_raw` | 30 days | Raw telemetry data points |
| `metrics_5m` | 180 days | 5-minute downsampled aggregates |
| `metrics_1h` | 730 days | 1-hour downsampled aggregates |

### Flux Downsampling Tasks

Two Flux tasks in `priv/influxdb/tasks/` replace TimescaleDB continuous aggregates:
- `downsample_5m.flux` -- runs every 5 minutes, aggregates avg/max/min/count
- `downsample_1h.flux` -- runs every hour, same aggregation pattern

### Key Implementation Details

- **Instream config format**: `host: "localhost"` (bare hostname), `scheme: "http"` (separate), `auth: [method: :token, token: "..."]` (nested keyword)
- **Multi-yield Flux queries**: Return list-of-lists (one per yield block). Must `List.flatten/1` before processing.
- **Timestamps**: InfluxDB returns `_time` as nanosecond integers, not ISO8601 strings
- **Row format**: Query results are flat lists of maps with string keys (e.g., `%{"_value" => 42.5, "device_id" => "dev123"}`)

### Files Changed

| Action | Files |
|--------|-------|
| New | `influx_db.ex`, `backend.ex`, `influx_backend.ex`, `influx_case.ex`, `mocks.ex`, setup/task scripts |
| Modified | `metrics.ex`, `query_router.ex`, `alert_evaluator.ex`, all configs, CI, tests, docs |
| Deleted | `queries.ex` (TimescaleDB SQL), `metric.ex` (Ecto schema for removed table) |
| Migration | `remove_timescaledb.exs` (drops extension and metrics table) |

## Consequences

### Positive
1. No license friction for self-hosted deployments
2. PostgreSQL deployable on any managed service (no extension requirement)
3. Cleaner separation of concerns: relational data in PostgreSQL, time-series in InfluxDB
4. InfluxDB's TSM engine is purpose-built for time-series write/query patterns
5. Backend abstraction enables future storage swaps without consumer changes

### Negative
1. Two databases to operate and back up (PostgreSQL + InfluxDB)
2. Flux query language has a learning curve (different from SQL)
3. No JOINs between metrics and relational data (must query separately)
4. InfluxDB v2 series cardinality limits need monitoring (high-cardinality tags can degrade performance)
5. Test setup requires a running InfluxDB instance (added CI service container)

### Mitigations
- InfluxDB is lightweight (single binary, minimal config) compared to additional database complexity
- Backend abstraction isolates Flux queries to a single module
- Cardinality managed by using only 3 tags (device_id, path, source)
- InfluxDB test helper (`InfluxCase`) handles bucket cleanup automatically

## Validation

- 527 tests passing, 0 failures
- Zero compiler warnings
- CI green with InfluxDB service container
- Format clean (`mix format --check-formatted`)
- All 23 InfluxDB integration tests pass (insert, query, aggregation, rate)

## Related ADRs
- ADR-001: Time-Series Database (superseded by this migration)

## Review Schedule
**Last Reviewed:** 2026-02-12
**Next Review:** 2026-08-12

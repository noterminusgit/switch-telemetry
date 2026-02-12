# ADR-001: Time-Series Database

**Status:** Superseded
**Date:** 2026-02-10 (original), 2026-02-12 (superseded)

## Original Decision (Superseded)

Use TimescaleDB (PostgreSQL extension) as the primary time-series store.

## Revised Decision

Use **InfluxDB v2** for time-series metrics storage, keeping **PostgreSQL** (without TimescaleDB) for relational data.

## Context

TimescaleDB's Apache-only license on self-hosted installations restricts key features:
- Compression policies
- Continuous aggregates
- Advanced retention policies

These features require the TimescaleDB Community (non-Apache) license, which introduced deployment friction and migration failures. Rather than managing license constraints, we migrated the time-series layer to InfluxDB v2, which is fully open source for self-hosted use.

## Rationale

- **No license restrictions**: InfluxDB OSS v2 includes all features (retention, downsampling, Flux tasks) without license gates.
- **Purpose-built for metrics**: Native time-series optimizations, line protocol for high-throughput writes, Flux query language for aggregation.
- **Mature Elixir client**: `instream` hex package provides full InfluxDB v2 support (line protocol writes, Flux queries).
- **Built-in downsampling**: Flux tasks replace TimescaleDB continuous aggregates. Configured in `priv/influxdb/tasks/`.
- **Bucket retention**: Native per-bucket retention policies replace TimescaleDB `add_retention_policy`.
- **PostgreSQL stays simple**: Removing the TimescaleDB extension means standard PostgreSQL can be used on any managed service.

## Architecture

```
Collectors → InfluxDB v2 (metrics_raw, metrics_5m, metrics_1h buckets)
           → PostgreSQL (devices, dashboards, users, alerts, Oban jobs)
```

A `SwitchTelemetry.Metrics.Backend` behaviour provides the abstraction layer. The `InfluxBackend` module implements all metrics operations using Flux queries.

## Consequences

### Positive
- No license friction for self-hosted deployments
- PostgreSQL deployable on any managed service (no extension requirement)
- Cleaner separation: relational data in PostgreSQL, time-series in InfluxDB
- InfluxDB purpose-built query optimizations for time-series workloads

### Negative
- Two databases to operate and back up (PostgreSQL + InfluxDB)
- Flux query language is a new syntax to learn (vs SQL)
- No JOINs between metrics and relational data (must query separately)
- InfluxDB v2 cardinality limits need monitoring for high-tag-count scenarios

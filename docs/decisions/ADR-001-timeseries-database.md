# ADR-001: TimescaleDB for Time-Series Storage

**Status:** Accepted
**Date:** 2026-02-10

## Context

We need a database to store billions of telemetry data points from thousands of network devices. Requirements: high ingestion rate (100k+ metrics/sec), efficient time-range queries, data retention policies, and compatibility with the Elixir/Ecto ecosystem.

## Decision

Use **TimescaleDB** (PostgreSQL extension) as the primary time-series store.

## Rationale

- **Ecto compatibility**: TimescaleDB is PostgreSQL. Standard `Ecto.Repo`, `Postgrex`, and `Ecto.Migration` work out of the box. No custom database adapter needed.
- **`timescale` hex package**: Provides `create_hypertable/2`, `time_bucket/2`, compression helpers, and hyperfunctions directly in Ecto queries.
- **Continuous aggregates**: Materialized views that auto-refresh, giving us pre-computed 5-minute and 1-hour rollups without application-level aggregation.
- **Compression**: 10:1+ compression for data older than 7 days, drastically reducing storage costs.
- **Retention policies**: Built-in `add_retention_policy` drops old chunks automatically.
- **SQL**: Full SQL power for ad-hoc queries, JOINs with device metadata, and complex analytics.
- **Single database**: Device inventory, dashboard configs, and metrics all live in one PostgreSQL instance. No operational overhead of managing a separate TSDB.

## Alternatives Considered

### InfluxDB
**Pros**: Purpose-built for metrics, excellent write performance, Flux query language.
**Cons**: No Ecto adapter. Requires a separate database and driver (`instream` hex package). Separate query language to learn. Cardinality issues with high-tag-count data (fixed in v3, but v3 has limited Elixir support).
**Rejected**: Added operational complexity of a second database with no Ecto integration.

### ClickHouse
**Pros**: Blazing fast analytics (2-3M points/sec ingestion), 10-30:1 compression, great for OLAP queries.
**Cons**: `ecto_ch` adapter exists but is less mature. No UPDATE support. Not ideal for the relational data (devices, dashboards) we also need to store. Overkill for our scale.
**Rejected**: We'd need both PostgreSQL (for relational data) AND ClickHouse (for metrics), doubling infrastructure.

### Plain PostgreSQL (no TimescaleDB)
**Pros**: Simplest setup, no extension to install.
**Cons**: No automatic partitioning, no built-in compression, no continuous aggregates, no retention policies. Query performance degrades severely beyond ~100M rows.
**Rejected**: We'll exceed 100M rows within weeks at scale.

## Consequences

### Positive
- Single database technology to operate and back up
- Familiar SQL for all queries
- Ecto integration means we use the same tools as the rest of the app
- Continuous aggregates solve the "are reads real-time?" concern elegantly

### Negative
- TimescaleDB extension must be installed on PostgreSQL (not available on all managed PG services, but available on Timescale Cloud, Aiven, AWS RDS with community AMI)
- Some advanced features (e.g., continuous aggregates with JOINs) require raw SQL `execute()` in migrations
- Horizontal write scaling requires TimescaleDB multi-node (more complex setup)

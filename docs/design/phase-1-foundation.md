# Feature: Phase 1 Foundation

## Problem

Switch Telemetry has comprehensive architecture documentation but no code implementation. We need to scaffold the Phoenix project, set up all dependencies, create the database layer (schemas + TimescaleDB migrations), configure dual releases (collector + web), and establish the conditional supervision tree.

## Proposed Solution

Use `mix phx.new` to generate a Phoenix 1.7+ project with LiveView. Layer on the domain-specific structure, dependencies, and configuration defined in the architecture docs.

### Key decisions for scaffolding:
- **Single OTP app** (not umbrella) — modules are namespaced by context (`Devices`, `Metrics`, `Collector`, `Dashboards`)
- **No built-in Phoenix dashboard** — we build our own with VegaLite/Tucan
- **No mailer** — not needed for telemetry platform
- **TimescaleDB** as the database — standard Postgres adapter with `timescale` extension

## Data Model Changes

### New tables (in migration order):

1. **timescaledb extension** — `CREATE EXTENSION IF NOT EXISTS timescaledb`
2. **credentials** — encrypted device authentication (Cloak.Ecto)
3. **devices** — network device inventory with ULID PKs
4. **subscriptions** — telemetry path definitions per device
5. **metrics** — TimescaleDB hypertable (partitioned by time)
6. **dashboards** — user dashboard configurations
7. **widgets** — individual chart widgets within dashboards
8. **metrics compression** — enable compression on metrics hypertable
9. **continuous aggregates** — 5-minute and 1-hour rollups
10. **retention policies** — 30d raw, 180d 5m, 730d 1h

### Ecto schemas:

| Schema | Module | PK | Notes |
|---|---|---|---|
| Credential | `SwitchTelemetry.Devices.Credential` | `:string` (ULID) | Cloak.Ecto encrypted fields |
| Device | `SwitchTelemetry.Devices.Device` | `:string` (ULID) | Tags as JSONB |
| Subscription | `SwitchTelemetry.Collector.Subscription` | `:string` (ULID) | Paths as array |
| Metric | `SwitchTelemetry.Metrics.Metric` | none (no PK) | Hypertable, append-only |
| Dashboard | `SwitchTelemetry.Dashboards.Dashboard` | `:string` (ULID) | |
| Widget | `SwitchTelemetry.Dashboards.Widget` | `:string` (ULID) | Queries as JSONB array |

## API / Interface

Phase 1 establishes the data layer only. No public API endpoints yet. Key internal interfaces:

- `SwitchTelemetry.Metrics.insert_batch/1` — batch insert metrics
- `SwitchTelemetry.Metrics.Queries.get_latest/2` — recent metrics for a device
- `SwitchTelemetry.Metrics.Queries.get_time_series/4` — time-bucketed aggregation
- `SwitchTelemetry.Devices.list_devices/0`, `get_device!/1`, `create_device/1`
- `SwitchTelemetry.Dashboards.get_dashboard!/1`

## Dependencies

### Hex packages:
- `phoenix`, `phoenix_live_view`, `phoenix_html`, `phoenix_live_dashboard` (standard Phoenix)
- `ecto_sql`, `postgrex` (database)
- `timescale` (TimescaleDB helpers)
- `vega_lite`, `tucan` (charting)
- `grpc`, `protobuf` (gNMI — stubs only in Phase 1)
- `sweet_xml` (NETCONF XML parsing)
- `horde` (distributed registry/supervisor)
- `libcluster` (BEAM clustering)
- `oban` (background jobs)
- `cloak_ecto` (credential encryption)
- `hash_ring` (consistent hashing)
- `jason` (JSON)
- `mox` (test mocks)
- `floki` (HTML test helpers)

### npm packages (assets/):
- `vega`, `vega-lite`, `vega-embed`

## Acceptance Criteria

1. `mix compile` succeeds with zero warnings
2. `mix test` passes (default Phoenix tests + any new schema tests)
3. `mix ecto.create && mix ecto.migrate` creates all tables and the hypertable (requires TimescaleDB)
4. `mix phx.server` starts in development with `NODE_ROLE=both`
5. `MIX_ENV=prod mix release collector` builds successfully
6. `MIX_ENV=prod mix release web` builds successfully
7. All 6 Ecto schemas load and validate changesets
8. VegaLite npm packages installed in assets/
9. VegaLiteHook JS file created and registered

# Plan: Phase 1 Foundation

## Prerequisites
- [x] Architecture documentation complete
- [x] VegaLite/Tucan decision finalized (ADR-003)
- [x] Elixir 1.17+ / OTP 27+ / Phoenix 1.7+ installed

## Tasks

### 1. Scaffold Phoenix project
**Files**: `mix.exs`, `config/`, `lib/`, `test/`, `assets/`, `.formatter.exs`, `.gitignore`
**Description**: Run `mix phx.new` with `--no-mailer --no-dashboard`. Preserve existing `docs/`, `CLAUDE.md`, `README.md`.
**Acceptance**: `mix compile` and `mix test` pass with default generated code.

### 2. Add hex dependencies
**Files**: `mix.exs`
**Description**: Add all project dependencies to `deps/0`. Run `mix deps.get`.
**Acceptance**: `mix deps.get` succeeds. `mix compile` succeeds (deps may have warnings, app code must not).

### 3. Create Credential schema and migration
**Files**: `lib/switch_telemetry/devices/credential.ex`, `priv/repo/migrations/*_create_timescaledb_extension.exs`, `priv/repo/migrations/*_create_credentials.exs`
**Test**: `test/switch_telemetry/devices/credential_test.exs`
**Description**: First migration enables TimescaleDB extension. Second creates credentials table with encrypted fields. Schema uses string PKs (ULID pattern).
**Acceptance**: Schema validates required fields. Migration runs. Changeset rejects nil username.

### 4. Create Device schema and migration
**Files**: `lib/switch_telemetry/devices/device.ex`, `priv/repo/migrations/*_create_devices.exs`
**Test**: `test/switch_telemetry/devices/device_test.exs`
**Description**: Devices table with ULID PK, all fields from domain model. Indexes on hostname (unique), ip_address (unique), status, assigned_collector, platform.
**Acceptance**: Schema validates required fields. Unique constraints enforced.

### 5. Create Devices context module
**Files**: `lib/switch_telemetry/devices.ex`
**Test**: `test/switch_telemetry/devices_test.exs`
**Description**: Context with `list_devices/0`, `get_device!/1`, `create_device/1`, `update_device/2`, `get_credential!/1`, `create_credential/1`.
**Acceptance**: CRUD operations work against database.

### 6. Create Subscription schema and migration
**Files**: `lib/switch_telemetry/collector/subscription.ex`, `priv/repo/migrations/*_create_subscriptions.exs`
**Test**: `test/switch_telemetry/collector/subscription_test.exs`
**Description**: Subscriptions table. FK to devices. Paths stored as array of strings.
**Acceptance**: Schema validates. FK constraint enforced.

### 7. Create Metric schema and migration (hypertable)
**Files**: `lib/switch_telemetry/metrics/metric.ex`, `priv/repo/migrations/*_create_metrics.exs`
**Test**: `test/switch_telemetry/metrics/metric_test.exs`
**Description**: Metrics table with NO primary key. Uses `flush()` then `create_hypertable`. Composite indexes include time column. Three value columns (float, int, str).
**Acceptance**: Migration creates hypertable. Schema maps all columns. `Repo.insert_all` works.

### 8. Create Metrics context with queries
**Files**: `lib/switch_telemetry/metrics.ex`, `lib/switch_telemetry/metrics/queries.ex`
**Test**: `test/switch_telemetry/metrics/queries_test.exs`
**Description**: `insert_batch/1` for bulk inserts. `Queries.get_latest/2` and `Queries.get_time_series/4` using time_bucket.
**Acceptance**: Batch insert works. Time-bucketed query returns aggregated results.

### 9. Create Dashboard and Widget schemas and migration
**Files**: `lib/switch_telemetry/dashboards/dashboard.ex`, `lib/switch_telemetry/dashboards/widget.ex`, `priv/repo/migrations/*_create_dashboards.exs`
**Test**: `test/switch_telemetry/dashboards/dashboard_test.exs`
**Description**: Dashboards table + widgets table. Widget queries stored as JSONB. Widget has FK to dashboard. Position stored as embedded map.
**Acceptance**: Dashboard with nested widgets creates successfully.

### 10. Create Dashboards context
**Files**: `lib/switch_telemetry/dashboards.ex`
**Test**: `test/switch_telemetry/dashboards_test.exs`
**Description**: `get_dashboard!/1` with preloaded widgets, `create_dashboard/1`, `add_widget/2`.
**Acceptance**: Dashboard CRUD with associated widgets works.

### 11. Create compression and aggregate migrations
**Files**: `priv/repo/migrations/*_compress_metrics.exs`, `priv/repo/migrations/*_create_metric_aggregates.exs`, `priv/repo/migrations/*_add_retention_policies.exs`
**Description**: Enable compression on metrics hypertable. Create 5-minute and 1-hour continuous aggregates. Add retention policies.
**Acceptance**: Migrations run without error (requires TimescaleDB).

### 12. Configure dual Mix releases
**Files**: `mix.exs` (project/0), `config/runtime.exs`
**Description**: Add `collector` and `web` release configurations. Runtime config uses NODE_ROLE for conditional Oban, Endpoint, and pool size settings.
**Acceptance**: `MIX_ENV=prod mix release collector` and `mix release web` both build.

### 13. Set up conditional supervision tree
**Files**: `lib/switch_telemetry/application.ex`
**Description**: Modify `start/2` to read NODE_ROLE and conditionally start common, collector, and web children. Common: Repo, PubSub, Cluster, Horde. Collector: DeviceManager (stub), Oban. Web: Endpoint, Telemetry.
**Acceptance**: App starts with NODE_ROLE=both (default), collector, or web without error.

### 14. Install VegaLite npm packages and create hook
**Files**: `assets/package.json`, `assets/js/hooks/vega_lite.js`, `assets/js/app.js`
**Description**: `npm install --save vega vega-lite vega-embed` in assets/. Create VegaLiteHook. Register in app.js.
**Acceptance**: `npm install` in assets/ succeeds. Hook file exists and is imported.

### 15. Verify full build
**Description**: Run `mix compile --warnings-as-errors`, `mix test`, `mix format --check-formatted`. Verify everything is green.
**Acceptance**: Zero warnings, all tests pass, code is formatted.

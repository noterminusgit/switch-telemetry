# Switch Telemetry

A distributed network telemetry collection and visualization platform built with Elixir, Phoenix LiveView, InfluxDB v2, and PostgreSQL.

## Overview

Switch Telemetry is a modular platform for collecting, storing, and visualizing network device telemetry at scale. It connects to network devices using **gNMI** (gRPC Network Management Interface) and **NETCONF** (RFC 6241) protocols, persists time-series metrics in **InfluxDB v2** and relational data in **PostgreSQL**, and serves interactive dashboards via **Phoenix LiveView** with **VegaLite/Tucan** charting.

The system scales horizontally by separating data collection and UI workloads across different BEAM VM nodes within a single distributed cluster.

## Architecture

```
                    +-----------+
                    |   Load    |
                    | Balancer  |
                    +-----+-----+
                          |
              +-----------+-----------+
              |                       |
        +-----+------+        +------+-----+
        | Web Node 1 |        | Web Node 2 |
        +-----+------+        +------+-----+
              |                       |
              +------ BEAM Cluster ---+----------+
              |                       |          |
        +-----+------+   +-----+------+  +------+-----+
        | Collector 1|   | Collector 2|  | Collector 3|
        +-----+------+   +-----+------+  +------+-----+
              |                 |                |
        [gNMI/NETCONF]   [gNMI/NETCONF]  [gNMI/NETCONF]
              |                 |                |
              +---------+------+-------+--------+
                        |              |
                  +-----+-----+ +-----+-----+
                  | InfluxDB   | | PostgreSQL|
                  | (metrics)  | | (relat.)  |
                  +------------+ +-----------+
```

### Node Types

The codebase produces two distinct Mix release targets controlled by the `NODE_ROLE` environment variable:

- **Collector nodes** (`NODE_ROLE=collector`) -- headless BEAM VMs that maintain gRPC streams and SSH/NETCONF sessions to network devices, writing telemetry to InfluxDB and broadcasting updates via Phoenix.PubSub
- **Web nodes** (`NODE_ROLE=web`) -- Phoenix LiveView servers that serve dashboards, subscribe to real-time PubSub broadcasts, and query InfluxDB for historical data
- **Both** (`NODE_ROLE=both`, default in dev) -- runs both roles in a single BEAM instance

All nodes form a single BEAM cluster via `libcluster`, enabling transparent PubSub messaging across node boundaries.

### Project Structure

```
lib/
  switch_telemetry/
    accounts/           # User auth, roles, admin allowlist
    alerting/           # Alert rules, events, evaluation
    collector/          # gNMI and NETCONF protocol clients
      gnmi_session.ex   # GenServer per device for gRPC streaming
      netconf_session.ex # GenServer per device for SSH/NETCONF
      device_manager.ex # Starts/stops sessions, tracks assignments
    dashboards/         # User dashboard configuration
    devices/            # Device inventory context
    metrics/            # Telemetry data context
      backend.ex        # Behaviour for metrics backends
      influx_backend.ex # InfluxDB v2 implementation
    workers/            # Oban background workers
    influx_db.ex        # Instream connection module
  switch_telemetry_web/
    live/               # LiveView modules
      dashboard_live.ex
      device_live.ex
    components/         # VegaLite/Tucan chart components
      telemetry_chart.ex
    controllers/        # Auth, session controllers
```

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Elixir 1.17+ / OTP 27+ |
| Web | Phoenix 1.7+ / LiveView 1.0+ / Bandit |
| Charting | VegaLite + Tucan (Elixir) / vega + vega-lite + vega-embed (npm) |
| Time-series DB | InfluxDB v2 (Flux queries, line protocol writes) via Instream |
| Relational DB | PostgreSQL 16+ via Ecto 3.x |
| gNMI | `grpc` + `protobuf` hex packages |
| NETCONF | Erlang `:ssh` (port 830) + SweetXml |
| Clustering | libcluster + Horde (distributed supervisor/registry) |
| Jobs | Oban |
| Encryption | Cloak (AES-256-GCM at rest) + Bcrypt (passwords) |
| CSS | Tailwind CSS v4 |
| JS bundling | esbuild |

## Prerequisites

- **Elixir 1.17+** and **Erlang/OTP 27+** -- managed via [mise](https://mise.jdx.dev/)
- **PostgreSQL 16+**
- **InfluxDB v2** (open source) with the `influx` CLI
- **Node.js / npm** (for Vega chart dependencies in `assets/`)

### Version Management with mise

This project uses `mise` to manage Elixir and Erlang versions (see `mise.toml`):

```toml
[tools]
elixir = "1.17.3-otp-27"
erlang = "27.2.1"
```

Install mise, then:

```bash
mise install
```

This ensures you get the correct Elixir/OTP versions. The system-installed Elixir is likely too old.

## Getting Started

```bash
# 1. Install Elixir/Erlang via mise
mise install

# 2. Install Elixir dependencies
mix deps.get

# 3. Install npm dependencies (required for VegaLite charts)
npm install --prefix assets

# 4. Set up PostgreSQL database (creates, migrates, seeds admin account)
mix ecto.setup

# 5. Set up InfluxDB buckets
#    Requires a running InfluxDB v2 instance and the `influx` CLI
./priv/influxdb/setup.sh

# 6. Run the dev server
mix phx.server
```

The app is available at http://localhost:4000.

### One-liner setup

```bash
mix setup
```

This runs: `deps.get` -> `ecto.setup` -> `assets.setup` -> `assets.build`. You still need to run `npm install --prefix assets` and `./priv/influxdb/setup.sh` separately.

## Default Admin Account

The seed script (`priv/repo/seeds.exs`) creates a default admin account:

| Field | Value |
|-------|-------|
| Email | `admin@switch-telemetry.local` |
| Password | `Admin123!secure` |
| Role | `admin` |

This account is auto-confirmed and added to the admin email allowlist.

### Resetting the Admin Password via iex

If you need to reset the admin password (or any user's password), connect to the running app:

```bash
# Development
iex -S mix

# Production release
bin/switch_telemetry remote
```

Then reset the password (minimum 12 characters):

```elixir
user = SwitchTelemetry.Accounts.get_user_by_email("admin@switch-telemetry.local")
SwitchTelemetry.Accounts.reset_user_password(user, %{password: "NewSecurePassword1"})
```

To change a user's role:

```elixir
user = SwitchTelemetry.Accounts.get_user_by_email("someone@example.com")
user |> SwitchTelemetry.Accounts.User.role_changeset(%{role: :admin}) |> SwitchTelemetry.Repo.update()
```

## Troubleshooting

### Filesystem Watcher Issues (watchman)

On Linux, Phoenix's live reload file watcher may require `inotify-tools` or fall back to polling. If you see watchman-related errors or file change detection doesn't work:

```bash
# Install inotify-tools (Ubuntu/Debian)
sudo apt-get install inotify-tools

# If you hit the inotify watch limit
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Phoenix does **not** require watchman itself -- it uses `file_system` (inotify on Linux, fsevents on macOS). If you previously installed watchman and it's conflicting, you can safely remove it.

### VegaLite / vega-embed Build Errors

If charts fail to render or esbuild reports missing modules for `vega`, `vega-lite`, or `vega-embed`:

```bash
# Install npm dependencies
npm install --prefix assets

# Verify esbuild can resolve them (NODE_PATH is configured in config.exs)
mix assets.build
```

The esbuild config in `config/config.exs` includes `assets/node_modules` in `NODE_PATH` so vega packages resolve correctly. If you still see resolution errors, verify that `assets/node_modules/vega-embed/` exists.

### Tailwind CSS Styles Not Rendering

Tailwind v4 is used with the standalone CLI (not PostCSS). If styles appear broken:

```bash
# Rebuild assets
mix assets.build

# Or in dev, restart the server (watchers auto-rebuild)
mix phx.server
```

The CSS entry point is `assets/css/app.css` which uses `@import "tailwindcss"` and `@source` directives to scan templates.

## InfluxDB Setup

InfluxDB v2 stores all time-series metrics. The setup script creates four buckets:

| Bucket | Retention | Purpose |
|--------|-----------|---------|
| `metrics_raw` | 30 days | Raw metric ingestion |
| `metrics_5m` | 180 days | 5-minute downsampled aggregates |
| `metrics_1h` | 730 days | 1-hour downsampled aggregates |
| `metrics_test` | None | Test bucket |

```bash
# Default: localhost:8086, dev-token, switch-telemetry org
./priv/influxdb/setup.sh

# Custom host/token/org
./priv/influxdb/setup.sh http://influxdb:8086 my-token my-org
```

Downsampling Flux tasks are in `priv/influxdb/tasks/` and can be deployed with `priv/influxdb/deploy_tasks.sh`.

### InfluxDB Environment Variables

| Variable | Default (dev) | Description |
|----------|---------------|-------------|
| `INFLUXDB_HOST` | `localhost` | InfluxDB hostname |
| `INFLUXDB_PORT` | `8086` | InfluxDB port |
| `INFLUXDB_SCHEME` | `http` | `http` or `https` |
| `INFLUXDB_TOKEN` | `dev-token` | API token |
| `INFLUXDB_ORG` | `switch-telemetry` | Organization name |
| `INFLUXDB_BUCKET` | `metrics_raw` | Default write bucket |

## Production Releases

```bash
# Build releases
MIX_ENV=prod mix release collector
MIX_ENV=prod mix release web

# Required environment variables
export DATABASE_URL="ecto://user:pass@host/switch_telemetry_prod"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export CLOAK_KEY="$(openssl rand -base64 32)"
export INFLUXDB_TOKEN="your-production-token"
export INFLUXDB_ORG="your-org"
export NODE_ROLE="web"  # or "collector"

# Run
_build/prod/rel/web/bin/switch_telemetry start
```

### Docker Compose (Development)

```bash
docker-compose up
```

This starts PostgreSQL, a web node, and a collector node. Note: InfluxDB is not included in docker-compose and must be run separately.

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run a specific test file
mix test test/switch_telemetry/metrics/influx_backend_test.exs

# Static analysis
mix dialyzer
```

Tests use `Ecto.Adapters.SQL.Sandbox` for PostgreSQL isolation and `SwitchTelemetry.InfluxCase` for InfluxDB integration tests (async: false).

## Documentation

See `docs/` for comprehensive architecture documentation:

- `docs/architecture/` -- system design, domain model, data layer, process architecture
- `docs/decisions/` -- Architecture Decision Records (ADRs)
- `docs/guardrails/` -- coding standards, review checklists
- `docs/HANDOFF.md` -- quick-start guide for AI agent collaboration

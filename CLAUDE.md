# CLAUDE.md - AI Agent Context for Switch Telemetry

## Project Context

Distributed network telemetry platform. Collector nodes connect to network devices via gNMI (gRPC) and NETCONF (SSH) to gather metrics. Web nodes serve Phoenix LiveView dashboards with VegaLite/Tucan charts. InfluxDB v2 stores time-series metrics; PostgreSQL stores relational data. All nodes form a single BEAM cluster.

**Status**: Phases 1-11 complete. 1485 tests + 25 property tests. Zero warnings.

## Architecture

- **Dual database**: InfluxDB v2 (metrics via Flux) + PostgreSQL (relational via Ecto)
- **Dual releases**: `mix release collector` / `mix release web`. `NODE_ROLE` env var controls supervision children
- **PubSub bridge**: `:pg` adapter broadcasts metrics from collectors to web nodes cluster-wide
- **Horde**: Distributed registry + supervisor for globally unique device sessions
- **Supervision**: Common (Repo, InfluxDB, Vault, PubSub, Horde, Finch, GRPC) → Collector (DeviceAssignment, NodeMonitor, DeviceManager, StreamMonitor, Oban) → Web (Telemetry, Endpoint)

## Project Structure

```
lib/switch_telemetry/
  application.ex, repo.ex, mailer.ex, influx_db.ex
  vault.ex, encrypted.ex          # Cloak AES-256-GCM encryption
  authorization.ex                # can?(user, action, resource)
  accounts/                       # Users, tokens, roles, magic links
  devices/                        # Device + Credential schemas, CRUD
  collector/                      # gNMI/NETCONF sessions, subscriptions, assignment
  metrics/                        # Backend behaviour, InfluxBackend, QueryRouter
  dashboards/                     # Dashboard + Widget schemas, cloning
  alerting/                       # Rules, events, channels, evaluator, notifier
  settings/                       # SMTP + security settings (single-row)
  workers/                        # 5 Oban workers (alerts, discovery, cleanup)

lib/switch_telemetry_web/
  components/                     # TelemetryChart, WidgetEditor, TimeRangePicker, nav
  controllers/                    # PageController, UserSessionController
  live/                           # alert, credential, dashboard, device, stream,
                                  # subscription, user (index/show/edit/form patterns)
```

## Key Patterns

**Contexts**: 7 Phoenix contexts — Accounts, Devices, Collector, Metrics, Dashboards, Alerting, Settings. Standard CRUD (`list_*`, `get_*!`, `create_*`, `update_*`, `delete_*`, `change_*`).

**Metrics backend**: `SwitchTelemetry.Metrics.Backend` behaviour (`insert_batch/1`, `get_latest/2`, `query/3`, `query_raw/4`, `query_rate/4`). Active backend via `:metrics_backend` app env.

**Behaviours for testability**: `GrpcClient` (7 callbacks), `SshClient` (5 callbacks) with `Default*` implementations wrapping GRPC.Stub / Erlang `:ssh`. Dispatched via `Application.get_env`. Mox mocks in `test/support/mocks.ex`.

**String IDs**: All schemas use `"prefix_" <> Base.encode32(:crypto.strong_rand_bytes(15))`. Prefixes: `dev_`, `cred_`, `sub_`, `dash_`, `wgt_`, `rule_`, `evt_`, `chan_`, `bind_`, `usr_`.

**Auth**: Session-based + magic links. Roles: `:admin` (all), `:operator` (devices/alerts/own dashboards), `:viewer` (read-only). `Authorization.can?/3` predicate. Plugs in `user_auth.ex`, LiveView on_mount hooks.

**InfluxDB writes**: `%{measurement, tags: %{device_id, path, source}, fields: %{value_float, ...}, timestamp: nanoseconds}`. Row maps use string keys (`"_time"`, `"_value"`). **Must `List.flatten/1`** multi-yield results.

**QueryRouter**: ≤1h → `metrics_raw`, 1-24h → `metrics_5m`, >24h → `metrics_1h`.

**PubSub topics**: `"device:#{id}"` (metrics), `"stream_monitor"` (stream status), `"alerts"` / `"alerts:#{device_id}"` (alert events).

## Common Mistakes

1. **Persist metrics** — Always write to InfluxDB AND broadcast via PubSub, never store only in GenServer state
2. **Subscribe, don't poll** — Use PubSub for real-time; query InfluxDB only for initial load and historical views
3. **SweetXml, not regex** — Parse NETCONF XML with `xpath/2`, never regex
4. **Survive code purge** — Use `Task.Supervisor.start_child` + `Process.monitor`, not `Task.async` in long-lived GenServers
5. **No Flux injection** — Never interpolate user input into Flux queries; use validated DB data only
6. **Flatten multi-yield** — `InfluxDB.query/1` returns `[[...], [...]]` for multi-yield; always `List.flatten/1`
7. **Oban runs on collectors** — Oban only starts on collector nodes; enqueue from anywhere, process on collectors

See [docs/reference/CONVENTIONS.md](docs/reference/CONVENTIONS.md) for full code examples.

## Environment

**mise** manages Erlang 27.2.1 + Elixir 1.17.3-otp-27. **Every bash command** must be prefixed with:
```bash
eval "$(/home/dude/.local/bin/mise activate bash)"
```

Key env vars: `NODE_ROLE` (`"both"`), `DATABASE_URL`, `INFLUXDB_HOST/PORT/TOKEN/ORG/BUCKET`, `CLOAK_KEY`, `SECRET_KEY_BASE`, `PHX_HOST`.

## Reference Docs

- [docs/reference/CONTEXTS.md](docs/reference/CONTEXTS.md) — All 7 context APIs, 14 schemas, auth rules, behaviours
- [docs/reference/INFRASTRUCTURE.md](docs/reference/INFRASTRUCTURE.md) — Tech stack, InfluxDB, PubSub, Oban, charting, env vars
- [docs/reference/CONVENTIONS.md](docs/reference/CONVENTIONS.md) — Common mistake code examples, testing patterns, naming

## AI Agent Configuration

Use up to 10 subagents in parallel. Maximize concurrent Task tool usage for independent operations.

**Director**: Designs features, writes specs in `docs/design/`, creates plans in `docs/plans/`. Does NOT write code. See `docs/guardrails/DIRECTOR_ROLE.md`.

**Implementor**: Executes plans using TDD. Writes tests first, then implementation. See `docs/guardrails/IMPLEMENTOR_ROLE.md`.

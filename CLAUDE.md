# CLAUDE.md - AI Agent Context for Switch Telemetry

## Project Context

Switch Telemetry is a distributed network telemetry platform. Collector nodes connect to network devices via gNMI (gRPC) and NETCONF (SSH) to gather metrics. Web nodes serve Phoenix LiveView dashboards with VegaLite/Tucan interactive charts. InfluxDB v2 stores all time-series metrics data; PostgreSQL stores relational data (devices, dashboards, users, alerts). All nodes form a single BEAM cluster.

**Status**: Phases 1-11 complete. 1485 tests + 25 property tests. Zero warnings. CI green.

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

## Architecture Overview

**Dual database**: InfluxDB v2 for time-series metrics (Flux queries, line protocol writes), PostgreSQL for relational data (Ecto/Postgrex).

**Dual releases**: `mix release collector` and `mix release web`. `NODE_ROLE` env var (`"collector"`, `"web"`, or `"both"`) controls which supervision children start.

**PubSub bridge**: Phoenix.PubSub with `:pg` adapter broadcasts metrics from collectors to web nodes cluster-wide. No message broker needed.

**Horde**: Distributed registry + supervisor for globally unique device sessions. If a collector crashes, Horde restarts sessions on surviving nodes.

**Supervision tree**:
```
Common (all nodes):   Repo, InfluxDB, Vault, PubSub, Horde.Registry, Horde.DynamicSupervisor, Finch, GRPC.Client.Supervisor
Collector only:       DeviceAssignment, NodeMonitor, DeviceManager, StreamMonitor, Oban
Web only:             Telemetry, Endpoint
```

## Project Structure

```
lib/switch_telemetry/
  application.ex              # Supervision tree, NODE_ROLE-based child selection
  repo.ex                     # Ecto repo
  mailer.ex                   # Swoosh mailer
  vault.ex                    # Cloak Vault (AES-256-GCM encryption)
  encrypted.ex                # Cloak encrypted type modules
  authorization.ex            # can?(user, action, resource) predicate
  influx_db.ex                # Instream connection module
  settings.ex                 # Settings context (SMTP, security)

  accounts/                   # User auth context
    accounts.ex               # Context: registration, login, tokens, roles, magic links
    user.ex                   # Schema: email, hashed_password, role
    user_token.ex             # Schema: session/reset/magic-link tokens
    user_notifier.ex          # Email delivery for auth flows
    admin_email.ex            # Schema: admin email allowlist

  devices/                    # Device inventory context
    devices.ex                # Context: CRUD, collector assignment, credentials
    device.ex                 # Schema: hostname, ip, platform, transport, ports, status
    credential.ex             # Schema: name, username, encrypted password/keys/certs

  collector/                  # Protocol collection
    collector.ex              # Context: subscription CRUD, toggle
    device_manager.ex         # Starts/stops gNMI/NETCONF sessions per device
    device_assignment.ex      # HashRing-based assignment of devices to collectors
    node_monitor.ex           # Monitors BEAM cluster membership changes
    stream_monitor.ex         # Tracks stream status, broadcasts via PubSub
    connection_tester.ex      # Tests device connectivity before session start
    gnmi_session.ex           # GenServer per device for gRPC streaming
    gnmi_capabilities.ex      # gNMI Capabilities RPC
    grpc_client.ex            # Behaviour + DefaultGrpcClient (wraps GRPC.Stub)
    netconf_session.ex        # GenServer per device for SSH/NETCONF
    ssh_client.ex             # Behaviour + DefaultSshClient (wraps Erlang :ssh)
    subscription.ex           # Schema: paths, mode, encoding, enabled
    subscription_paths.ex     # Platform-specific path definitions from priv/gnmi_paths/
    tls_helper.ex             # TLS credential loading for gNMI connections
    gnmi/proto/               # Compiled protobuf: gnmi.pb.ex, gnmi.service.ex

  metrics/                    # Metrics storage context
    metrics.ex                # Context: insert_batch, get_latest, get_time_series
    backend.ex                # Behaviour: 5 callbacks for metric storage
    influx_backend.ex         # InfluxDB v2 implementation (Flux queries)
    query_router.ex           # Routes queries to appropriate downsampled bucket

  dashboards/                 # Dashboard context
    dashboards.ex             # Context: CRUD, clone, widgets, device/path pickers
    dashboard.ex              # Schema: name, layout, refresh_interval, is_public, tags
    widget.ex                 # Schema: title, chart_type, position, time_range, queries

  alerting/                   # Alerting context
    alerting.ex               # Context: rules/channels/events/bindings CRUD
    alert_rule.ex             # Schema: condition, threshold, severity, state, cooldown
    alert_event.ex            # Schema: status, value, message, metadata (audit log)
    notification_channel.ex   # Schema: type (webhook/slack/email), config, enabled
    alert_channel_binding.ex  # Schema: join table rule ↔ channel
    evaluator.ex              # Pure function: evaluate_rule against metric data
    notifier.ex               # Delivers notifications via webhook/Slack/email

  settings/                   # Application settings
    security_setting.ex       # Schema: require_secure_gnmi, require_credentials
    smtp_setting.ex           # Schema: relay, port, from, tls, enabled (encrypted password)

  workers/                    # Oban workers
    alert_evaluator.ex        # Every minute: evaluate all enabled alert rules
    alert_notifier.ex         # On-demand: deliver alert notifications
    alert_event_pruner.ex     # Daily 3am: prune old alert events (30d retention)
    device_discovery.ex       # On-demand: assign devices via HashRing
    stale_session_cleanup.ex  # On-demand: clean Horde sessions from dead nodes

lib/switch_telemetry_web/
  endpoint.ex, router.ex, user_auth.ex, telemetry.ex, gettext.ex

  components/
    core_components.ex        # Phoenix CoreComponents
    layouts.ex                # Layout component + templates in layouts/
    telemetry_chart.ex        # VegaLite/Tucan LiveComponent
    time_range_picker.ex      # Time range selector component
    widget_editor.ex          # Dashboard widget builder
    sidebar.ex, top_bar.ex, mobile_nav.ex  # Navigation chrome

  controllers/
    page_controller.ex        # Landing page
    user_session_controller.ex # Login/logout (+ session HTML templates)
    error_html.ex, error_json.ex

  live/
    alert_live/               # index.ex, rule_form.ex, channel_form.ex
    credential_live/          # index.ex, edit.ex, show.ex
    dashboard_live/           # index.ex, show.ex
    device_live/              # index.ex, show.ex, edit.ex
    stream_live/              # monitor.ex (real-time stream status)
    subscription_live/        # index.ex, form_component.ex
    user_live/                # index.ex (admin user management), settings.ex
```

## Domain Contexts

### Accounts (`SwitchTelemetry.Accounts`)
Registration, login, session tokens, password reset, email confirmation, magic links, role management, admin email allowlist. Key: `register_user/1`, `get_user_by_email_and_password/2`, `generate_user_session_token/1`, `update_user_role/2`, `deliver_magic_link_instructions/2`, `verify_magic_link_token/1`, `get_or_create_user_for_magic_link/1`.

### Devices (`SwitchTelemetry.Devices`)
Device and credential CRUD, collector assignment. Key: `list_devices/0`, `create_device/1`, `list_devices_for_collector/1`, `get_device_with_credential!/1`, `get_device_with_subscriptions!/1`, `default_gnmi_encoding/1`, `list_credentials_for_select/0`.

### Collector (`SwitchTelemetry.Collector`)
Subscription CRUD and control. Key: `list_subscriptions/0`, `list_subscriptions_for_device/1`, `create_subscription/1`, `toggle_subscription/1`.

### Metrics (`SwitchTelemetry.Metrics`)
Thin facade delegating to configured backend. Key: `insert_batch/1`, `get_latest/2`, `get_time_series/4`.

### Dashboards (`SwitchTelemetry.Dashboards`)
Dashboard and widget CRUD, cloning, device/path pickers. Key: `create_dashboard/1`, `add_widget/2`, `clone_dashboard/2`, `list_device_options/0`, `list_paths_for_device/1`.

### Alerting (`SwitchTelemetry.Alerting`)
Alert rules, notification channels, events, and bindings. Key: `list_enabled_rules/0`, `create_alert_rule/1`, `bind_channel/2`, `create_event/1`, `update_rule_state/3`, `list_recent_events/1`.

### Settings (`SwitchTelemetry.Settings`)
SMTP and security settings (single-row pattern). Key: `get_smtp_settings/0`, `update_smtp_settings/1`, `get_security_settings/0`, `update_security_settings/1`.

## Behaviours & Abstractions

**Metrics.Backend** — 5 callbacks:
`insert_batch/1`, `get_latest/2`, `query/3`, `query_raw/4`, `query_rate/4`. Plus `query_by_prefix/3` on InfluxBackend.

**Collector.GrpcClient** — 7 callbacks:
`connect/2`, `disconnect/1`, `subscribe/1`, `send_request/2`, `recv/1`, `capabilities/2`, `capabilities/3`. Default: `DefaultGrpcClient` (wraps `GRPC.Stub`).

**Collector.SshClient** — 5 callbacks:
`connect/3`, `session_channel/2`, `subsystem/4`, `send/3`, `close/1`. Default: `DefaultSshClient` (wraps Erlang `:ssh`).

**Dispatch pattern**: `Application.get_env(:switch_telemetry, :grpc_client, DefaultGrpcClient)`. Test config overrides with Mox mocks defined in `test/support/mocks.ex`:
- `SwitchTelemetry.Metrics.MockBackend`
- `SwitchTelemetry.Collector.MockGrpcClient`
- `SwitchTelemetry.Collector.MockSshClient`

## InfluxDB & Metrics

**Buckets**: `metrics_raw` (30d), `metrics_5m` (180d), `metrics_1h` (730d), `metrics_test` (no retention).

**Write format**: `%{measurement: "metrics", tags: %{device_id, path, source}, fields: %{value_float, value_int, value_str}, timestamp: nanoseconds}`.

**Row maps**: String keys — `"_time"`, `"_value"`, `"_field"`, `"device_id"`, `"path"`, `"result"`.

**Multi-yield gotcha**: `InfluxDB.query/1` returns list-of-lists for multi-yield Flux. **Must `List.flatten/1`** before processing.

**QueryRouter bucket selection**:
- ≤ 1 hour → `metrics_raw` (10s aggregation)
- 1–24 hours → `metrics_5m`
- \> 24 hours → `metrics_1h`

**`query_by_prefix/3`**: Converts subscription paths to Flux regex allowing optional `[key=val]` selectors between segments. E.g., `/interfaces/interface/state/counters` matches `/interfaces/interface[name=Gi0/0/0]/state/counters/in-octets`. Returns `[%{path: String.t(), data: [%{bucket: DateTime, avg_value: float}]}]`.

**Env vars**: `INFLUXDB_HOST`, `INFLUXDB_PORT`, `INFLUXDB_SCHEME`, `INFLUXDB_TOKEN`, `INFLUXDB_ORG`, `INFLUXDB_BUCKET`.

## PubSub Topics

| Topic | Message | Publisher | Subscriber |
|-------|---------|-----------|------------|
| `"device:#{id}"` | `{:gnmi_metrics, id, metrics}` | GnmiSession | DeviceLive.Show, DashboardLive.Show |
| `"device:#{id}"` | `{:netconf_metrics, id, metrics}` | NetconfSession | DeviceLive.Show, DashboardLive.Show |
| `"stream_monitor"` | `{:stream_update, status}` | StreamMonitor | StreamLive.Monitor |
| `"stream_monitor"` | `{:streams_full, [statuses]}` | StreamMonitor | StreamLive.Monitor |
| `"alerts"` | `{:alert_event, event}` | AlertEvaluator | AlertLive.Index |
| `"alerts:#{device_id}"` | `{:alert_event, event}` | AlertEvaluator | (device-scoped) |

## Auth & Authorization

**Session-based** with remember-me cookie (60 days). Magic link authentication for passwordless login.

**Roles**: `:admin` (full access), `:operator` (devices, alerts, own dashboards), `:viewer` (read-only, public dashboards + own dashboards).

**`Authorization.can?(user, action, resource)`** — pattern-matched predicate:
- Admin: all actions on all resources
- Operator: view all, create/edit devices and alert rules, create dashboards, edit/delete own dashboards
- Viewer: view devices, alerts, dashboard list, public dashboards, own dashboards
- Default: deny

**Plugs**: `fetch_current_user`, `require_authenticated_user`, `require_admin` (in `user_auth.ex`).

**LiveView on_mount hooks**: `:mount_current_user`, `:ensure_authenticated`, `:ensure_admin`.

**Encryption**: Cloak Vault (AES-256-GCM) encrypts credential passwords, SSH keys, TLS certs/keys, SMTP password. Type: `SwitchTelemetry.Encrypted.Binary`.

## Oban Workers & Queues

| Worker | Queue | Schedule | Max Attempts | Description |
|--------|-------|----------|-------------|-------------|
| AlertEvaluator | `alerts` | `* * * * *` (every minute) | 1 | Evaluate all enabled alert rules |
| AlertNotifier | `notifications` | On-demand | 5 | Deliver webhook/Slack/email notifications |
| AlertEventPruner | `maintenance` | `0 3 * * *` (daily 3am) | 1 | Prune events older than 30 days |
| DeviceDiscovery | `discovery` | On-demand | 3 | Assign devices to collectors via HashRing |
| StaleSessionCleanup | `maintenance` | On-demand | 3 | Clean Horde sessions from dead nodes |

**Queue config**: `default: 10, discovery: 2, maintenance: 1, notifications: 5, alerts: 1`.

## Charting

**TelemetryChart** (`SwitchTelemetryWeb.Components.TelemetryChart`): LiveComponent that builds VegaLite specs and pushes to browser via `VegaLiteHook`.

**Assigns**: `series` (list), `chart_type` (atom), `width`, `height`, `responsive` (boolean), `title` (optional).

**Series format**: `[%{label: "name", data: [%{time: DateTime.t(), value: float()}]}]`.

**Chart types**: `:line`, `:area`, `:bar`, `:points` (VegaLite mark: `"point"`). Falls back to `:line`.

**JS hook**: `VegaLite` in `assets/js/hooks/vega_lite.js`. Also: `DashboardGrid` in `assets/js/hooks/dashboard_grid.js`.

**npm deps**: `vega`, `vega-lite`, `vega-embed`.

## Code Conventions

### Naming
- Modules: `SwitchTelemetry.Collector.GnmiSession`, `SwitchTelemetry.Devices.Device`
- LiveView: `SwitchTelemetryWeb.DashboardLive.Show`, `SwitchTelemetryWeb.DeviceLive.Index`
- Workers: `SwitchTelemetry.Workers.AlertEvaluator`
- Components: `SwitchTelemetryWeb.Components.TelemetryChart`

### IDs
All schemas use string IDs (`autogenerate: false`), generated at creation time:
```elixir
"dev_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
```
Prefixes: `dev_`, `cred_`, `sub_`, `dash_`, `wgt_`, `rule_`, `evt_`, `chan_`, `bind_`, `usr_`.

### Testing
- `ExUnit` with `async: true` where possible
- `Mox` for protocol behaviours (GrpcClient, SshClient, Backend)
- `Ecto.Adapters.SQL.Sandbox` for PostgreSQL tests
- `SwitchTelemetry.InfluxCase` for InfluxDB integration tests (`async: false`, `Process.sleep(100)` for read-after-write)
- `StreamData` for property-based tests (protocol parsing)
- `lazy_html` required as test dep for Phoenix LiveView 1.1+

## Common Mistakes

```elixir
# ❌ DON'T: Store device state only in GenServer memory
def handle_info(:collect, %{device: device} = state) do
  metrics = collect_from_device(device)
  {:noreply, %{state | last_metrics: metrics}}
end

# ✅ DO: Write to InfluxDB AND broadcast via PubSub
def handle_info(:collect, %{device: device} = state) do
  with {:ok, metrics} <- collect_from_device(device) do
    SwitchTelemetry.Metrics.insert_batch(device.id, metrics)
    Phoenix.PubSub.broadcast(SwitchTelemetry.PubSub, "device:#{device.id}", {:metrics, metrics})
    {:noreply, state}
  end
end
```

```elixir
# ❌ DON'T: Query InfluxDB in a tight loop from LiveView
def handle_info(:tick, socket) do
  metrics = Metrics.get_latest(id, limit: 100)
  {:noreply, assign(socket, metrics: metrics)}
end

# ✅ DO: Subscribe to PubSub for real-time, query only for initial load
def mount(params, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(PubSub, "device:#{params["id"]}")
  metrics = Metrics.get_latest(params["id"], limit: 100)
  {:ok, assign(socket, metrics: metrics)}
end
```

```elixir
# ❌ DON'T: Parse NETCONF XML with regex
{:ok, hostname} = Regex.run(~r/<hostname>(.*)<\/hostname>/, xml_response)

# ✅ DO: Use SweetXml for XPath
import SweetXml
hostname = xml_response |> xpath(~x"//hostname/text()"s)
```

```elixir
# ❌ DON'T: Use Task.async closures in long-lived GenServers
# BEAM code purge during hot reload kills the Task, crashing the GenServer
def handle_info(:poll, state) do
  task = Task.async(fn -> query_device(state.device) end)
  {:noreply, %{state | task: task}}
end

# ✅ DO: Use Task.Supervisor with monitored tasks that survive code purge
def handle_info(:poll, state) do
  {:ok, pid} = Task.Supervisor.start_child(TaskSup, fn -> query_device(state.device) end)
  ref = Process.monitor(pid)
  {:noreply, %{state | task_ref: ref}}
end
```

```elixir
# ❌ DON'T: Interpolate user input into Flux queries
flux = ~s(from(bucket: "metrics_raw") |> filter(fn: (r) => r.path == "#{user_path}"))

# ✅ DO: Validate and sanitize paths before use in Flux
# Subscription.changeset already validates: ^/[a-zA-Z0-9/_\-\.:]+$
# Always use validated data from the database, never raw user input
```

```elixir
# ❌ DON'T: Forget List.flatten on multi-yield InfluxDB results
results = InfluxDB.query(flux_with_multiple_yields)
Enum.map(results, &process/1)  # results is [[row, ...], [row, ...]]

# ✅ DO: Always flatten multi-yield results
results = InfluxDB.query(flux_with_multiple_yields) |> List.flatten()
Enum.map(results, &process/1)
```

```elixir
# ❌ DON'T: Run Oban workers on web-only nodes
# Oban only starts on collector nodes (see application.ex)

# ✅ DO: Ensure jobs are enqueued from any node but only processed by collectors
# Oban uses PostgreSQL, so inserts work from any node. Processing happens on collectors.
```

## Environment & Development

**mise** manages Erlang 27.2.1 + Elixir 1.17.3-otp-27 (see `mise.toml` in project root).

**Every bash command** must be prefixed with:
```bash
eval "$(/home/dude/.local/bin/mise activate bash)"
```

**Key env vars**:

| Variable | Description | Default |
|----------|-------------|---------|
| `NODE_ROLE` | `"collector"`, `"web"`, or `"both"` | `"both"` |
| `DATABASE_URL` | PostgreSQL connection string | — |
| `INFLUXDB_HOST` | InfluxDB hostname | `"localhost"` |
| `INFLUXDB_PORT` | InfluxDB port | `8086` |
| `INFLUXDB_TOKEN` | InfluxDB auth token | — |
| `INFLUXDB_ORG` | InfluxDB organization | — |
| `INFLUXDB_BUCKET` | InfluxDB bucket name | — |
| `CLOAK_KEY` | Base64-encoded AES-256 key | — |
| `SECRET_KEY_BASE` | Phoenix secret | — |
| `PHX_HOST` | Public hostname | `"localhost"` |

**Releases**: `mix release collector`, `mix release web`.

## AI Agent Configuration

Use up to 10 subagents in parallel when working on this project. Maximize concurrent Task tool usage for independent operations like research, file exploration, code generation, and testing.

## AI Agent Roles

**Director**: Designs features, writes specs in `docs/design/`, creates plans in `docs/plans/`. Does NOT write implementation code. See `docs/guardrails/DIRECTOR_ROLE.md`.

**Implementor**: Executes plans using TDD. Writes tests first, then implementation. Reports blockers to Director. See `docs/guardrails/IMPLEMENTOR_ROLE.md`.

# CLAUDE.md - AI Agent Context for Switch Telemetry

## Project Context

Switch Telemetry is a distributed network telemetry platform. Collector nodes connect to network devices via gNMI (gRPC) and NETCONF (SSH) to gather metrics. Web nodes serve Phoenix LiveView dashboards with VegaLite/Tucan interactive charts. InfluxDB v2 stores all time-series metrics data; PostgreSQL stores relational data (devices, dashboards, users, alerts). All nodes form a single BEAM cluster.

## Key Architectural Decisions

1. **InfluxDB v2 for time-series, PostgreSQL for relational** -- InfluxDB handles all metric ingestion and querying via Flux. PostgreSQL (standard Ecto/Postgrex) stores device inventory, dashboards, users, alerts, and Oban jobs. The `instream` hex package provides the Elixir client. Downsampling is handled by InfluxDB Flux tasks (5m and 1h aggregation buckets).

2. **Two release types, one codebase** -- `mix release collector` and `mix release web` produce different binaries from the same source. The `NODE_ROLE` environment variable controls which supervision children start.

3. **Phoenix.PubSub as the real-time bridge** -- Collectors broadcast metrics via PubSub; web nodes subscribe. The `:pg` adapter works transparently across BEAM nodes. No message broker needed.

4. **gNMI via elixir-grpc** -- The `grpc` hex package (v0.11+) handles gRPC client connections. Proto files are compiled with `protobuf`. Each device gets a GenServer that manages a bidirectional gNMI Subscribe stream.

5. **NETCONF via Erlang :ssh** -- No production-ready NETCONF library exists for Elixir. We build a custom client using `:ssh.connect/3` and `:ssh_connection.subsystem/4` on port 830. XML responses are parsed with SweetXml.

6. **VegaLite/Tucan for charting** -- Client-side interactive rendering. Tucan provides a high-level API (`lineplot`, `area`, `bar`, `scatter`) that generates VegaLite specs. Specs are pushed to the browser via LiveView hooks and rendered by the Vega JavaScript runtime. Uses `:temporal` encoding for time axes, `:quantitative` for metric values. Rich built-in interactivity (tooltips, zoom, pan). Requires `vega`, `vega-lite`, `vega-embed` npm packages.

7. **Horde for distributed device sessions** -- Each device session is globally unique across the cluster. Horde.DynamicSupervisor starts sessions on collector nodes. Horde.Registry provides cluster-wide name resolution. If a collector crashes, Horde restarts sessions on surviving nodes.

8. **Metrics backend abstraction** -- A `SwitchTelemetry.Metrics.Backend` behaviour defines `insert_batch/1`, `get_latest/2`, `query/3`, `query_raw/4`, `query_rate/4`. The active backend is configured via `:metrics_backend` app env. `InfluxBackend` is the production implementation. Metrics are tagged by `device_id`, `path`, `source` with typed value fields (`value_float`, `value_int`, `value_str`).

## Code Conventions

### Naming
- Modules: `SwitchTelemetry.Collector.GnmiSession`, `SwitchTelemetry.Collector.NetconfSession`
- Schemas: `SwitchTelemetry.Devices.Device`
- LiveView: `SwitchTelemetryWeb.DashboardLive`, `SwitchTelemetryWeb.DeviceLive`
- Workers: `SwitchTelemetry.Workers.DeviceDiscovery`

### Structure
```
lib/
  switch_telemetry/
    collector/          # gNMI and NETCONF protocol clients
      gnmi_session.ex   # GenServer per device for gRPC streaming
      netconf_session.ex # GenServer per device for SSH/NETCONF
      device_manager.ex # Starts/stops sessions, tracks assignments
    devices/            # Device inventory context
      device.ex         # Ecto schema
    metrics/            # Telemetry data context
      backend.ex        # Behaviour for metrics backends
      influx_backend.ex # InfluxDB v2 implementation
    dashboards/         # User dashboard configuration context
      dashboard.ex      # Ecto schema
      widget.ex         # Dashboard widget configuration
    workers/            # Oban workers
    influx_db.ex        # Instream connection module
  switch_telemetry_web/
    live/               # LiveView modules
      dashboard_live.ex
      device_live.ex
    components/         # VegaLite/Tucan chart components
      telemetry_chart.ex
```

### Testing
- Use `ExUnit` with `async: true` where possible
- Mock external device connections with `Mox`
- Use `Ecto.Adapters.SQL.Sandbox` for PostgreSQL tests
- Use `SwitchTelemetry.InfluxCase` for InfluxDB integration tests (`async: false`)
- Property-based tests with `StreamData` for protocol parsing

## Common Mistakes

```elixir
# ❌ DON'T: Store device state only in GenServer memory
# If the process crashes, all session state is lost
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

# ✅ DO: Subscribe to PubSub for real-time, query DB only for initial load and historical views
def mount(params, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(PubSub, "device:#{params["id"]}")
  metrics = Metrics.get_latest(params["id"], limit: 100)
  {:ok, assign(socket, metrics: metrics)}
end

def handle_info({:metrics, new_metrics}, socket) do
  {:noreply, assign(socket, metrics: prepend_and_trim(socket.assigns.metrics, new_metrics, 100))}
end
```

```elixir
# ❌ DON'T: Parse NETCONF XML with regex
{:ok, hostname} = Regex.run(~r/<hostname>(.*)<\/hostname>/, xml_response)

# ✅ DO: Use SweetXml for XPath
import SweetXml
hostname = xml_response |> xpath(~x"//hostname/text()"s)
```

## AI Agent Configuration

Use up to 10 subagents in parallel when working on this project. Maximize concurrent Task tool usage for independent operations like research, file exploration, code generation, and testing.

## AI Agent Roles

**Director**: Designs features, writes specs in `docs/design/`, creates plans in `docs/plans/`. Does NOT write implementation code.

**Implementor**: Executes plans using TDD. Writes tests first, then implementation. Reports blockers to Director.

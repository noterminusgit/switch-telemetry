# Code Conventions & Common Mistakes

## Naming

- Modules: `SwitchTelemetry.Collector.GnmiSession`, `SwitchTelemetry.Devices.Device`
- LiveView: `SwitchTelemetryWeb.DashboardLive.Show`, `SwitchTelemetryWeb.DeviceLive.Index`
- Workers: `SwitchTelemetry.Workers.AlertEvaluator`
- Components: `SwitchTelemetryWeb.Components.TelemetryChart`

## IDs

All schemas use string IDs (`autogenerate: false`), generated at creation time:
```elixir
"dev_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
```
Prefixes: `dev_`, `cred_`, `sub_`, `dash_`, `wgt_`, `rule_`, `evt_`, `chan_`, `bind_`, `usr_`.

## Testing

- `ExUnit` with `async: true` where possible
- `Mox` for protocol behaviours (GrpcClient, SshClient, Backend)
- `Ecto.Adapters.SQL.Sandbox` for PostgreSQL tests
- `SwitchTelemetry.InfluxCase` for InfluxDB integration tests (`async: false`, `Process.sleep(100)` for read-after-write consistency)
- `StreamData` for property-based tests (protocol parsing)
- `lazy_html` required as test dep for Phoenix LiveView 1.1+
- Test support files in `test/support/`: `conn_case.ex`, `data_case.ex`, `influx_case.ex`, `mocks.ex`

## Common Mistakes — Full Examples

### 1. Persist metrics — don't store only in GenServer state

```elixir
# ❌ DON'T
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

### 2. Subscribe, don't poll — use PubSub for real-time

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

### 3. SweetXml, not regex — for NETCONF XML parsing

```elixir
# ❌ DON'T
{:ok, hostname} = Regex.run(~r/<hostname>(.*)<\/hostname>/, xml_response)

# ✅ DO
import SweetXml
hostname = xml_response |> xpath(~x"//hostname/text()"s)
```

### 4. Survive code purge — Task.async dies during hot reload

```elixir
# ❌ DON'T: Task.async closures in long-lived GenServers
def handle_info(:poll, state) do
  task = Task.async(fn -> query_device(state.device) end)
  {:noreply, %{state | task: task}}
end

# ✅ DO: Use Task.Supervisor with monitored tasks
def handle_info(:poll, state) do
  {:ok, pid} = Task.Supervisor.start_child(TaskSup, fn -> query_device(state.device) end)
  ref = Process.monitor(pid)
  {:noreply, %{state | task_ref: ref}}
end
```

### 5. No Flux injection — never interpolate user input

```elixir
# ❌ DON'T
flux = ~s(from(bucket: "metrics_raw") |> filter(fn: (r) => r.path == "#{user_path}"))

# ✅ DO: Use validated data from the database, never raw user input
# Subscription.changeset validates paths: ^/[a-zA-Z0-9/_\-\.:]+$
```

### 6. Flatten multi-yield — InfluxDB returns nested lists

```elixir
# ❌ DON'T
results = InfluxDB.query(flux_with_multiple_yields)
Enum.map(results, &process/1)  # results is [[row, ...], [row, ...]]

# ✅ DO
results = InfluxDB.query(flux_with_multiple_yields) |> List.flatten()
Enum.map(results, &process/1)
```

### 7. Oban runs on collectors — not web nodes

```elixir
# ❌ DON'T: Assume Oban workers run on web nodes
# Oban only starts on collector nodes (see application.ex)

# ✅ DO: Enqueue from any node, process on collectors
# Oban uses PostgreSQL — inserts work from any node, processing on collectors only
```

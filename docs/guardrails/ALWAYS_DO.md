# ALWAYS DO: Mandatory Practices

## Data Integrity

### 1. Always Write Metrics to InfluxDB Before Broadcasting
```elixir
# Persist first, then notify
Metrics.insert_batch(metrics)
Phoenix.PubSub.broadcast(PubSub, "device:#{device_id}", {:metrics, metrics})
```
If PubSub broadcast fails, data is still durably stored. If insert fails, don't broadcast stale/missing data.

### 2. Always Use Batch Inserts for Metrics
```elixir
# ✅ Batch insert (one InfluxDB write call)
Metrics.insert_batch(entries)

# ❌ Individual inserts (N round-trips)
Enum.each(entries, &Metrics.insert_batch([&1]))
```
At 100k metrics/sec, individual inserts would overwhelm the InfluxDB connection.

### 3. Always Include Time Range in InfluxDB Queries
```elixir
# ✅ Bounded Flux query
from(bucket: "metrics_raw") |> range(start: -1h)

# ❌ Unbounded query (scans entire bucket)
from(bucket: "metrics_raw") |> filter(fn: (r) => r.device_id == id)
```
InfluxDB requires `range()` for efficient time-series queries. Without it, the query scans all data in the bucket.

### 4. Always Use Downsampled Buckets for Dashboard Queries > 1 Hour
```elixir
# The QueryRouter and InfluxBackend handle this automatically:
# <= 1h  → metrics_raw bucket with aggregateWindow
# 1-24h  → metrics_5m bucket (pre-aggregated by Flux task)
# > 24h  → metrics_1h bucket (pre-aggregated by Flux task)
QueryRouter.query(device_id, path, time_range)
```

## Protocol Sessions

### 5. Always Implement Exponential Backoff for Reconnection
```elixir
defp schedule_retry(state) do
  delay = min(:timer.seconds(5) * :math.pow(2, state.retry_count), :timer.minutes(5))
  Process.send_after(self(), :connect, trunc(delay))
end
```
Prevents thundering herd when a device or network recovers.

### 6. Always Register Device Sessions with Horde
```elixir
GenServer.start_link(__MODULE__, opts,
  name: {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:gnmi, device.id}}}
)
```
Ensures exactly one session per device across the entire cluster.

### 7. Always Handle BEAM Code Purge in Long-Running Tasks
```elixir
# ✅ Distinguish code reload kills from real crashes
def handle_info({:DOWN, ref, :process, _pid, :killed}, %{task_ref: ref, channel: ch} = state)
    when ch != nil do
  # Channel is still alive — resubscribe immediately
  send(self(), :subscribe)
  {:noreply, %{state | stream: nil, task_ref: nil}}
end

def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
  # Real crash — full reconnect with backoff
  schedule_retry(state)
  {:noreply, %{state | stream: nil, task_ref: nil}}
end
```
`Task.async` closures bind to the module version. After two recompiles, BEAM purges the oldest version and kills any process running it with reason `:killed`. GenServer callbacks are safe (dispatched via fully-qualified calls), but long-running Tasks are not.

### 8. Always Handle SSH/gRPC Connection Errors Gracefully
```elixir
case :ssh.connect(ip, port, opts) do
  {:ok, ref} -> {:noreply, %{state | ssh_ref: ref}}
  {:error, reason} ->
    Logger.warning("SSH failed: #{inspect(reason)}")
    schedule_retry(state)
    {:noreply, state}
end
```
Network devices are unreliable. Never let a connection failure crash the session permanently.

## LiveView & UI

### 9. Always Subscribe to PubSub in `mount/3` When `connected?/1` is True
```elixir
def mount(params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(PubSub, "device:#{params["id"]}")
  end
  {:ok, socket}
end
```
The `connected?/1` guard prevents subscribing during the static HTML render.

### 10. Always Trim Chart Data to a Maximum Point Count
```elixir
defp append_and_trim(existing, new_points, max \\ 500) do
  (existing ++ new_points)
  |> Enum.take(-max)
end
```
Unbounded data accumulation in LiveView assigns causes memory growth and large SVG DOM.

### 11. Always Use `:temporal` Encoding for VegaLite Time Axes
```elixir
# ✅ Correct: temporal encoding handles timestamps with auto-formatting
VegaLite.encode_field(:x, "time", type: :temporal)

# ❌ Wrong: quantitative encoding with Unix timestamps loses date formatting
VegaLite.encode_field(:x, "time", type: :quantitative)
```
Convert DateTime values to ISO 8601 strings before including in VegaLite data.

## Architecture

### 12. Always Conditionally Start Supervision Children Based on NODE_ROLE
```elixir
defp collector_children(role) when role in ["collector", "both"], do: [...]
defp collector_children(_), do: []
```

### 13. Always Use the Backend Abstraction for Metrics Operations
```elixir
# ✅ Use the Metrics context (delegates to configured backend)
Metrics.insert_batch(metrics)
Metrics.get_latest(device_id, limit: 100)

# ❌ Don't call InfluxDB directly from business logic
SwitchTelemetry.InfluxDB.write(points)
```

### 14. Always Tag Metrics with Device ID and Source Protocol
```elixir
%{device_id: device.id, source: "gnmi", path: path, ...}
```
Enables filtering and debugging by source.

### 15. Always Use SweetXml for NETCONF XML Parsing
```elixir
import SweetXml
hostname = xml |> xpath(~x"//system/hostname/text()"s)
interfaces = xml |> xpath(~x"//interface"l, name: ~x"./name/text()"s, status: ~x"./admin-status/text()"s)
```

## Testing

### 16. Always Mock Device Connections with Mox
```elixir
# test/support/mocks.ex
Mox.defmock(SwitchTelemetry.Collector.GnmiClientMock, for: SwitchTelemetry.Collector.GnmiClientBehaviour)

# In tests
expect(GnmiClientMock, :subscribe, fn _channel, _request -> {:ok, mock_stream()} end)
```

### 17. Always Use Ecto Sandbox for Database Tests
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(SwitchTelemetry.Repo)
end
```

### 18. Always Test Protocol Parsing with Real Vendor Output Fixtures
Keep sample gNMI notifications and NETCONF XML responses in `test/fixtures/` from each supported vendor (Cisco, Juniper, Arista, Nokia).

## Operations

### 19. Always Set Data Retention Policies
```bash
# InfluxDB bucket retention is configured at bucket creation time:
influx bucket create -n metrics_raw -r 720h    # 30 days
influx bucket create -n metrics_5m  -r 4320h   # 180 days
influx bucket create -n metrics_1h  -r 17520h  # 730 days
# See priv/influxdb/setup.sh for the full setup script.
```

### 20. Always Monitor Collector Session Counts via Telemetry
```elixir
:telemetry.execute([:switch_telemetry, :collector, :active_sessions], %{count: count})
```
If session count drops unexpectedly, a collector node may have failed.

### 21. Always Encrypt Credentials at Rest
```elixir
# Use Cloak.Ecto for transparent field-level encryption
field :password, SwitchTelemetry.Encrypted.Binary
```

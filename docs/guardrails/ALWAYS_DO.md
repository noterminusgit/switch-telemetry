# ALWAYS DO: Mandatory Practices

## Data Integrity

### 1. Always Write Metrics to TimescaleDB Before Broadcasting
```elixir
# Persist first, then notify
Metrics.insert_batch(metrics)
Phoenix.PubSub.broadcast(PubSub, "device:#{device_id}", {:metrics, metrics})
```
If PubSub broadcast fails, data is still durably stored. If insert fails, don't broadcast stale/missing data.

### 2. Always Use Batch Inserts for Metrics
```elixir
# ✅ Batch insert (one round-trip)
Repo.insert_all("metrics", entries)

# ❌ Individual inserts (N round-trips)
Enum.each(entries, &Repo.insert/1)
```
At 100k metrics/sec, individual inserts would overwhelm the database connection pool.

### 3. Always Include Time Range in Metric Queries
```elixir
# ✅ Bounded query
from(m in "metrics", where: m.time > ago(1, "hour"))

# ❌ Unbounded query (scans entire hypertable)
from(m in "metrics", where: m.device_id == ^id)
```
TimescaleDB uses time-based chunk pruning. Without a time predicate, it scans all chunks.

### 4. Always Use Continuous Aggregates for Dashboard Queries > 1 Hour
```elixir
def query_for_range(range) do
  duration = DateTime.diff(range.end, range.start)
  cond do
    duration <= 3600  -> query_raw_table(range)
    duration <= 86400 -> query_5m_aggregate(range)
    true              -> query_1h_aggregate(range)
  end
end
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

### 7. Always Handle SSH/gRPC Connection Errors Gracefully
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

### 8. Always Subscribe to PubSub in `mount/3` When `connected?/1` is True
```elixir
def mount(params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(PubSub, "device:#{params["id"]}")
  end
  {:ok, socket}
end
```
The `connected?/1` guard prevents subscribing during the static HTML render.

### 9. Always Trim Chart Data to a Maximum Point Count
```elixir
defp append_and_trim(existing, new_points, max \\ 500) do
  (existing ++ new_points)
  |> Enum.take(-max)
end
```
Unbounded data accumulation in LiveView assigns causes memory growth and large SVG DOM.

### 10. Always Use `:temporal` Encoding for VegaLite Time Axes
```elixir
# ✅ Correct: temporal encoding handles timestamps with auto-formatting
VegaLite.encode_field(:x, "time", type: :temporal)

# ❌ Wrong: quantitative encoding with Unix timestamps loses date formatting
VegaLite.encode_field(:x, "time", type: :quantitative)
```
Convert DateTime values to ISO 8601 strings before including in VegaLite data.

## Architecture

### 11. Always Conditionally Start Supervision Children Based on NODE_ROLE
```elixir
defp collector_children(role) when role in ["collector", "both"], do: [...]
defp collector_children(_), do: []
```

### 12. Always Use `flush()` Between Table Creation and Hypertable Conversion
```elixir
create table(:metrics, ...) do ... end
flush()
create_hypertable(:metrics, :time)
```

### 13. Always Tag Metrics with Device ID and Source Protocol
```elixir
%{device_id: device.id, source: "gnmi", path: path, ...}
```
Enables filtering and debugging by source.

### 14. Always Use SweetXml for NETCONF XML Parsing
```elixir
import SweetXml
hostname = xml |> xpath(~x"//system/hostname/text()"s)
interfaces = xml |> xpath(~x"//interface"l, name: ~x"./name/text()"s, status: ~x"./admin-status/text()"s)
```

## Testing

### 15. Always Mock Device Connections with Mox
```elixir
# test/support/mocks.ex
Mox.defmock(SwitchTelemetry.Collector.GnmiClientMock, for: SwitchTelemetry.Collector.GnmiClientBehaviour)

# In tests
expect(GnmiClientMock, :subscribe, fn _channel, _request -> {:ok, mock_stream()} end)
```

### 16. Always Use Ecto Sandbox for Database Tests
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(SwitchTelemetry.Repo)
end
```

### 17. Always Test Protocol Parsing with Real Vendor Output Fixtures
Keep sample gNMI notifications and NETCONF XML responses in `test/fixtures/` from each supported vendor (Cisco, Juniper, Arista, Nokia).

## Operations

### 18. Always Set Data Retention Policies
```sql
SELECT add_retention_policy('metrics', INTERVAL '30 days');
SELECT add_retention_policy('metrics_5m', INTERVAL '180 days');
SELECT add_retention_policy('metrics_1h', INTERVAL '730 days');
```

### 19. Always Monitor Collector Session Counts via Telemetry
```elixir
:telemetry.execute([:switch_telemetry, :collector, :active_sessions], %{count: count})
```
If session count drops unexpectedly, a collector node may have failed.

### 20. Always Encrypt Credentials at Rest
```elixir
# Use Cloak.Ecto for transparent field-level encryption
field :password, SwitchTelemetry.Encrypted.Binary
```

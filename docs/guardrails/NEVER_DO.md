# NEVER DO: Critical Prohibitions

## 1. Never Store Metrics in GenServer State as Source of Truth
```elixir
# ❌ NEVER
def handle_info({:metrics, data}, state) do
  {:noreply, %{state | metrics_cache: [data | state.metrics_cache]}}
end

# ✅ ALWAYS: Write to InfluxDB, broadcast via PubSub
def handle_info({:metrics, data}, state) do
  Metrics.insert_batch(data)
  Phoenix.PubSub.broadcast(PubSub, "device:#{state.device_id}", {:metrics, data})
  {:noreply, state}
end
```
**Why**: Process crashes lose all in-memory data. InfluxDB (metrics) and PostgreSQL (relational) are the sources of truth.

## 2. Never Query InfluxDB in a Tight Loop from LiveView
```elixir
# ❌ NEVER: Polling the database every second
:timer.send_interval(1000, :refresh)
def handle_info(:refresh, socket) do
  data = Metrics.get_latest(id, limit: 100)
  {:noreply, assign(socket, data: data)}
end

# ✅ ALWAYS: Subscribe to PubSub, query InfluxDB only on mount and range changes
Phoenix.PubSub.subscribe(PubSub, "device:#{id}")
```
**Why**: PubSub delivers real-time data with zero DB load. Polling creates N*M queries (N dashboards * M widgets).

## 3. Never Parse XML with Regex
```elixir
# ❌ NEVER
Regex.run(~r/<hostname>(.*?)<\/hostname>/, xml)

# ✅ ALWAYS
import SweetXml
xpath(xml, ~x"//hostname/text()"s)
```
**Why**: XML is not a regular language. Regex fails on namespaces, CDATA, nested elements, encoding variations.

## 4. Never Hardcode Device Credentials
```elixir
# ❌ NEVER
:ssh.connect(ip, 830, [user: ~c"admin", password: ~c"cisco123"])

# ✅ ALWAYS: Load from encrypted credential store
credential = Devices.get_credential!(device.credentials_id)
:ssh.connect(ip, 830, [user: charlist(credential.username), password: charlist(decrypt(credential.password))])
```
**Why**: Credentials in source code are a security vulnerability. Use Cloak.Ecto for at-rest encryption.

## 5. Never Query InfluxDB Without a Time Range
```elixir
# ❌ NEVER: Unbounded Flux query (scans entire bucket)
flux = ~s|from(bucket: "metrics_raw") |> filter(fn: (r) => r.device_id == "#{id}")|

# ✅ ALWAYS: Include a range() call to bound the query
flux = ~s|from(bucket: "metrics_raw") |> range(start: -1h) |> filter(fn: (r) => r.device_id == "#{id}")|
```
**Why**: InfluxDB requires a time range for efficient queries. Unbounded queries scan all data in the bucket and may timeout or exhaust memory.

## 6. Never Block the Request Path with Device Connections
```elixir
# ❌ NEVER: Connecting to a device in a LiveView mount
def mount(params, _session, socket) do
  {:ok, channel} = GRPC.Stub.connect("#{device.ip}:#{device.port}")
  {:ok, assign(socket, channel: channel)}
end

# ✅ ALWAYS: Device connections live in collector-node GenServers
# LiveView reads from DB and subscribes to PubSub
```
**Why**: SSH/gRPC connections take seconds and may timeout. Never block a user-facing request.

## 7. Never Interpolate Unsanitized User Input into Flux Queries
```elixir
# ❌ NEVER: Direct string interpolation of user input
flux = ~s|from(bucket: "metrics_raw") |> filter(fn: (r) => r.device_id == "#{user_input}")|

# ✅ ALWAYS: Escape special characters before interpolating
flux = ~s|from(bucket: "metrics_raw") |> filter(fn: (r) => r.device_id == "#{escape_flux(user_input)}")|

defp escape_flux(str) do
  str |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
end
```
**Why**: Unescaped input could break Flux query syntax or cause injection. Always sanitize strings before embedding in Flux queries.

## 8. Never Run Oban Workers on Web Nodes
```elixir
# ❌ NEVER: Starting Oban on web nodes
# config/runtime.exs
config :switch_telemetry, Oban, queues: [discovery: 2]  # on ALL nodes

# ✅ ALWAYS: Conditionally start Oban
if System.get_env("NODE_ROLE") in ["collector", "both"] do
  config :switch_telemetry, Oban, queues: [discovery: 2]
end
```
**Why**: Oban workers (device discovery, config backup) need collector-node resources. Running them on web nodes wastes resources and may cause unexpected device connections from web nodes.

## 9. Never Assume gNMI Path Format is Consistent Across Vendors
```elixir
# ❌ NEVER: Hardcoded path assumptions
path = "/interfaces/interface[name=Ethernet1]/state/counters/in-octets"

# ✅ ALWAYS: Normalize paths and handle vendor variations
# Cisco: /Cisco-IOS-XR-pfi-im-cmd-oper:interfaces/...
# Juniper: /junos/system/linecard/...
# Arista: /interfaces/interface[name=Ethernet1]/state/counters/in-octets (OpenConfig)
path = normalize_vendor_path(raw_path, device.platform)
```
**Why**: Even within OpenConfig, vendors use different YANG module origins and key formats.

## 10. Never Log Raw Credentials or Full XML Responses in Production
```elixir
# ❌ NEVER
Logger.info("Connecting with password: #{credential.password}")
Logger.debug("NETCONF response: #{xml_response}")  # may contain config secrets

# ✅ ALWAYS
Logger.info("Connecting to #{device.hostname} as #{credential.username}")
Logger.debug("NETCONF response received, #{byte_size(xml_response)} bytes")
```
**Why**: Logs are often shipped to centralized systems. Credentials and device configs in logs are a security risk.

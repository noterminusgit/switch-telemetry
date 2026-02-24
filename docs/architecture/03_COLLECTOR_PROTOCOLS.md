# 03: Collector Protocols (gNMI & NETCONF)

## gNMI (gRPC Network Management Interface)

### Overview

gNMI is an OpenConfig-defined protocol for streaming telemetry over gRPC/HTTP2. It uses Protocol Buffers for serialization and supports bidirectional streaming, making it ideal for real-time telemetry subscriptions.

### Vendor Support

| Vendor | Platform | gNMI Support | Notes |
|---|---|---|---|
| Cisco | IOS-XR 6.5.1+ | Full | Native OpenConfig + Cisco YANG models |
| Cisco | NX-OS 9.3+ | Full | OpenConfig models |
| Cisco | IOS-XE 16.12+ | Partial | Limited path support |
| Juniper | Junos 18.3+ | Partial | No gNMI Get RPC; use Subscribe |
| Arista | EOS 4.20+ | Full | Best OpenConfig support |
| Nokia | SR OS 19.7+ | Full | OpenConfig + Nokia YANG models |
| Nokia | SR Linux | Full | gNMI-native platform |

### Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:grpc, "~> 0.11"},          # gRPC client/server
    {:protobuf, "~> 0.14"},       # Protocol Buffer encoding
    {:gun, "~> 2.0"}              # HTTP/2 client (used by grpc)
  ]
end
```

### Proto Compilation

The gNMI proto file is maintained at `openconfig/gnmi` on GitHub. Download and compile:

```bash
# Download gnmi.proto
mkdir -p proto
curl -o proto/gnmi.proto https://raw.githubusercontent.com/openconfig/gnmi/master/proto/gnmi/gnmi.proto
curl -o proto/gnmi_ext.proto https://raw.githubusercontent.com/openconfig/gnmi/master/proto/gnmi_ext/gnmi_ext.proto

# Generate Elixir modules
protoc --elixir_out=plugins=grpc:./lib/switch_telemetry/collector/gnmi/proto \
  -I proto proto/gnmi.proto proto/gnmi_ext.proto
```

This generates:
- `Gnmi.GNMI.Stub` -- gRPC client stub with `subscribe/2`, `get/2`, `set/2`, `capabilities/2`
- `Gnmi.SubscribeRequest`, `Gnmi.SubscribeResponse` -- message types
- `Gnmi.Path`, `Gnmi.TypedValue`, `Gnmi.Update`, `Gnmi.Notification`

### gNMI Session GenServer

```elixir
defmodule SwitchTelemetry.Collector.GnmiSession do
  @moduledoc """
  Manages a gNMI streaming subscription to a single network device.
  One GenServer per device. Maintains a long-lived gRPC bidirectional stream.

  All gRPC calls are dispatched through `grpc_client/0`, which returns the
  active GrpcClient implementation (see "Behaviour Abstractions" section below).
  """
  use GenServer
  require Logger

  defstruct [:device, :channel, :stream, :task_ref, :retry_count, :credential]

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)
    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:gnmi, device.id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{device: device, retry_count: 0}}
  end

  @impl true
  def handle_info(:connect, state) do
    target = "#{state.device.ip_address}:#{state.device.gnmi_port}"

    case grpc_client().connect(target, []) do
      {:ok, channel} ->
        Logger.info("gNMI connected to #{state.device.hostname} at #{target}")
        send(self(), :subscribe)
        {:noreply, %{state | channel: channel, retry_count: 0}}

      {:error, reason} ->
        Logger.warning("gNMI connection failed for #{state.device.hostname}: #{inspect(reason)}")
        schedule_retry(state)
        {:noreply, %{state | retry_count: state.retry_count + 1}}
    end
  end

  def handle_info(:subscribe, state) do
    subscriptions = build_subscriptions(state.device)

    subscribe_request = %Gnmi.SubscribeRequest{
      request: {:subscribe, %Gnmi.SubscriptionList{
        subscription: subscriptions,
        mode: :STREAM,
        encoding: :PROTO
      }}
    }

    # Open bidirectional stream via the GrpcClient behaviour
    stream = grpc_client().subscribe(state.channel)

    # Send the subscription request
    grpc_client().send_request(stream, subscribe_request)

    # Spawn a task to read responses (non-blocking)
    task = Task.async(fn -> read_stream(stream, state.device) end)

    {:noreply, %{state | stream: stream, task_ref: task.ref}}
  end

  def handle_info({ref, :stream_ended}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    Logger.warning("gNMI stream ended for #{state.device.hostname}, reconnecting")
    schedule_retry(state)
    {:noreply, %{state | stream: nil, task_ref: nil}}
  end

  # Stream task killed by code purge during development recompilation.
  # Task.async closures bind to the module version. After two recompiles,
  # BEAM purges the oldest version and kills processes executing it.
  # The gRPC channel is still alive — just resubscribe immediately.
  def handle_info({:DOWN, ref, :process, _pid, :killed}, %{task_ref: ref, channel: ch} = state)
      when ch != nil do
    Logger.info("gNMI stream reader restarting for #{state.device.hostname} (code reload)")
    send(self(), :subscribe)
    {:noreply, %{state | stream: nil, task_ref: nil}}
  end

  # Stream task crashed for other reasons — full reconnect with backoff
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    Logger.error("gNMI stream task crashed for #{state.device.hostname}: #{inspect(reason)}")
    schedule_retry(state)
    {:noreply, %{state | stream: nil, task_ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.channel, do: grpc_client().disconnect(state.channel)
    :ok
  end

  # --- Private ---

  defp read_stream(stream, device) do
    case grpc_client().recv(stream) do
      {:ok, response_stream} ->
        response_stream
        |> Stream.each(fn
          {:ok, %Gnmi.SubscribeResponse{response: {:update, notification}}} ->
            metrics = parse_notification(device, notification)

            if metrics != [] do
              SwitchTelemetry.Metrics.insert_batch(metrics)

              Phoenix.PubSub.broadcast(
                SwitchTelemetry.PubSub,
                "device:#{device.id}",
                {:gnmi_metrics, device.id, metrics}
              )
            end

          {:ok, %Gnmi.SubscribeResponse{response: {:sync_response, true}}} ->
            Logger.debug("gNMI sync complete for #{device.hostname}")

          {:error, reason} ->
            Logger.error("gNMI stream error for #{device.hostname}: #{inspect(reason)}")
        end)
        |> Stream.run()

      {:error, reason} ->
        Logger.error("gNMI recv failed for #{device.hostname}: #{inspect(reason)}")
    end

    :stream_ended
  end

  defp parse_notification(device, %Gnmi.Notification{} = notif) do
    timestamp =
      case notif.timestamp do
        ts when is_integer(ts) and ts > 0 -> DateTime.from_unix!(ts, :nanosecond)
        _ -> DateTime.utc_now()
      end

    Enum.map(notif.update, fn %Gnmi.Update{path: path, val: typed_val} ->
      %{
        time: timestamp,
        device_id: device.id,
        path: format_path(notif.prefix, path),
        source: "gnmi",
        tags: extract_tags(path),
        value_float: extract_float(typed_val),
        value_int: extract_int(typed_val),
        value_str: extract_str(typed_val)
      }
    end)
  end

  defp format_path(prefix, %Gnmi.Path{elem: elems}) do
    prefix_elems = if prefix, do: prefix.elem || [], else: []
    all_elems = prefix_elems ++ (elems || [])

    "/" <> Enum.map_join(all_elems, "/", fn %Gnmi.PathElem{name: name, key: keys} ->
      if keys != nil and map_size(keys) > 0 do
        key_str = Enum.map_join(keys, ",", fn {k, v} -> "#{k}=#{v}" end)
        "#{name}[#{key_str}]"
      else
        name
      end
    end)
  end

  defp extract_float(%Gnmi.TypedValue{value: {:double_val, v}}), do: v
  defp extract_float(%Gnmi.TypedValue{value: {:float_val, v}}), do: v
  defp extract_float(_), do: nil

  defp extract_int(%Gnmi.TypedValue{value: {:int_val, v}}), do: v
  defp extract_int(%Gnmi.TypedValue{value: {:uint_val, v}}), do: v
  defp extract_int(_), do: nil

  defp extract_str(%Gnmi.TypedValue{value: {:string_val, v}}), do: v
  defp extract_str(_), do: nil

  defp extract_tags(%Gnmi.Path{elem: elems}) when is_list(elems) do
    Enum.reduce(elems, %{}, fn %Gnmi.PathElem{key: keys}, acc ->
      if keys != nil, do: Map.merge(acc, keys), else: acc
    end)
  end

  defp extract_tags(_), do: %{}

  defp build_subscriptions(device) do
    # Query subscriptions from DB and convert paths to gNMI Subscription structs
    # (simplified -- see gnmi_session.ex for full implementation)
    device
    |> SwitchTelemetry.Collector.Subscriptions.for_device()
    |> Enum.map(fn sub ->
      %Gnmi.Subscription{
        path: string_to_gnmi_path(sub.path),
        mode: :SAMPLE,
        sample_interval: sub.sample_interval_ns
      }
    end)
  end

  defp string_to_gnmi_path(path_string) do
    elems =
      path_string
      |> String.trim_leading("/")
      |> String.split("/")
      |> Enum.map(fn segment ->
        case Regex.run(~r/^([^\[]+)\[(.+)\]$/, segment) do
          [_, name, keys_str] ->
            keys = parse_path_keys(keys_str)
            %Gnmi.PathElem{name: name, key: keys}
          nil ->
            %Gnmi.PathElem{name: segment, key: %{}}
        end
      end)

    %Gnmi.Path{elem: elems}
  end

  defp parse_path_keys(keys_str) do
    keys_str
    |> String.split(",")
    |> Map.new(fn kv ->
      [k, v] = String.split(kv, "=", parts: 2)
      {k, v}
    end)
  end

  defp schedule_retry(state) do
    delay = min(
      trunc(:timer.seconds(5) * :math.pow(2, state.retry_count)),
      :timer.minutes(5)
    )
    Process.send_after(self(), :connect, delay)
  end

  # Dispatch to the configured GrpcClient implementation.
  # Defaults to DefaultGrpcClient in production; tests override via Application env.
  defp grpc_client do
    Application.get_env(
      :switch_telemetry,
      :grpc_client,
      SwitchTelemetry.Collector.DefaultGrpcClient
    )
  end
end
```

## NETCONF (Network Configuration Protocol)

### Overview

NETCONF (RFC 6241) is an XML-based network management protocol that runs over SSH. It's universally supported across network vendors and is the primary protocol for devices that don't support gNMI.

### Erlang SSH for NETCONF

There is no production-ready NETCONF client library for Elixir. We build one using Erlang's `:ssh` application, which provides SSH client functionality including subsystem invocation. All SSH calls are dispatched through `ssh_client/0`, which returns the active `SshClient` implementation (see "Behaviour Abstractions" section below).

```elixir
defmodule SwitchTelemetry.Collector.NetconfSession do
  @moduledoc """
  Manages a NETCONF session to a network device over SSH.
  Uses SweetXml for XML parsing. SSH operations are dispatched through
  `ssh_client/0` for testability (see "Behaviour Abstractions" section).
  """
  use GenServer
  require Logger
  import SweetXml

  @netconf_hello """
  <?xml version="1.0" encoding="UTF-8"?>
  <hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
    <capabilities>
      <capability>urn:ietf:params:netconf:base:1.0</capability>
      <capability>urn:ietf:params:netconf:base:1.1</capability>
    </capabilities>
  </hello>
  ]]>]]>
  """

  @framing_end "]]>]]>"
  @connect_timeout 10_000
  @channel_timeout 30_000

  defstruct [:device, :ssh_ref, :channel_id, :timer_ref, buffer: "", message_id: 1]

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)
    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:netconf, device.id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{device: device}}
  end

  @impl true
  def handle_info(:connect, state) do
    device = state.device
    credential = SwitchTelemetry.Devices.get_credential!(device.credential_id)

    ssh_opts = [
      {:user, String.to_charlist(credential.username)},
      {:silently_accept_hosts, true},
      {:connect_timeout, @connect_timeout}
    ]

    ssh_opts =
      if credential.password do
        [{:password, String.to_charlist(credential.password)} | ssh_opts]
      else
        ssh_opts
      end

    with {:ok, ssh_ref} <-
           ssh_client().connect(
             String.to_charlist(device.ip_address),
             device.netconf_port,
             ssh_opts
           ),
         {:ok, channel_id} <-
           ssh_client().session_channel(ssh_ref, @channel_timeout),
         :success <-
           ssh_client().subsystem(ssh_ref, channel_id, ~c"netconf", @channel_timeout) do

      Logger.info("NETCONF connected to #{device.hostname}")
      ssh_client().send(ssh_ref, channel_id, @netconf_hello)

      # Schedule periodic collection
      interval = device.collection_interval_ms || 30_000
      {:ok, timer_ref} = :timer.send_interval(interval, :collect)

      {:noreply, %{state | ssh_ref: ssh_ref, channel_id: channel_id, timer_ref: timer_ref}}
    else
      error ->
        Logger.error("NETCONF connection failed for #{device.hostname}: #{inspect(error)}")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, state}
    end
  end

  def handle_info(:collect, %{ssh_ref: nil} = state), do: {:noreply, state}

  def handle_info(:collect, state) do
    paths = get_subscription_paths(state.device)

    state =
      Enum.reduce(paths, state, fn path, acc ->
        rpc = build_get_rpc(acc.message_id, path)
        ssh_client().send(acc.ssh_ref, acc.channel_id, rpc)
        %{acc | message_id: acc.message_id + 1}
      end)

    {:noreply, state}
  end

  # Receive SSH data
  def handle_info({:ssh_cm, _ref, {:data, _channel, _type, data}}, state) do
    buffer = state.buffer <> to_string(data)
    {messages, remaining} = extract_messages(buffer)

    Enum.each(messages, fn msg ->
      handle_netconf_message(msg, state.device)
    end)

    {:noreply, %{state | buffer: remaining}}
  end

  def handle_info({:ssh_cm, _ref, {:closed, _channel}}, state) do
    Logger.warning("NETCONF session closed for #{state.device.hostname}, reconnecting")
    cleanup_ssh(state)
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | ssh_ref: nil, channel_id: nil, buffer: ""}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup_ssh(state)
    :ok
  end

  # --- Private ---

  defp handle_netconf_message(xml, device) do
    metrics = parse_netconf_response(xml, device)

    if metrics != [] do
      SwitchTelemetry.Metrics.insert_batch(metrics)

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:netconf_metrics, device.id, metrics}
      )
    end
  rescue
    e ->
      Logger.error("NETCONF parse error for #{device.hostname}: #{inspect(e)}")
  end

  defp parse_netconf_response(xml, device) do
    now = DateTime.utc_now()

    try do
      xml
      |> xpath(~x"//rpc-reply/data//*[text()]"l)
      |> Enum.map(fn element ->
        path = element_to_path(element)
        value = xpath(element, ~x"./text()"s)

        %{
          time: now,
          device_id: device.id,
          path: path,
          source: "netconf",
          tags: %{},
          value_float: parse_float(value),
          value_int: parse_int(value),
          value_str: if(numeric?(value), do: nil, else: value)
        }
      end)
    rescue
      _ -> []
    end
  end

  defp build_get_rpc(message_id, filter_path) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rpc message-id="#{message_id}" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
      <get>
        <filter type="subtree">
          #{filter_path}
        </filter>
      </get>
    </rpc>
    ]]>]]>
    """
  end

  defp element_to_path(element) do
    name = xpath(element, ~x"local-name(.)"s)
    "/" <> name
  end

  defp cleanup_ssh(state) do
    if state.timer_ref, do: :timer.cancel(state.timer_ref)
    if state.ssh_ref, do: ssh_client().close(state.ssh_ref)
  end

  defp parse_float(val) do
    case Float.parse(val) do
      {f, ""} -> f
      {f, _} -> if String.contains?(val, "."), do: f, else: nil
      :error -> nil
    end
  end

  defp parse_int(val) do
    case Integer.parse(val) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp numeric?(val), do: parse_float(val) != nil or parse_int(val) != nil

  # Dispatch to the configured SshClient implementation.
  # Defaults to DefaultSshClient in production; tests override via Application env.
  defp ssh_client do
    Application.get_env(
      :switch_telemetry,
      :ssh_client,
      SwitchTelemetry.Collector.DefaultSshClient
    )
  end
end
```

## Behaviour Abstractions for Testability

Both `GnmiSession` and `NetconfSession` depend on external systems (gRPC servers and SSH servers respectively). To enable unit testing without real network devices, all external calls are dispatched through behaviour-based abstractions.

### GrpcClient Behaviour

Defined in `lib/switch_telemetry/collector/grpc_client.ex`:

```elixir
defmodule SwitchTelemetry.Collector.GrpcClient do
  @moduledoc "Behaviour wrapping gRPC client operations for gNMI sessions."

  @callback connect(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback disconnect(term()) :: {:ok, term()}
  @callback subscribe(term()) :: term()
  @callback send_request(term(), term()) :: term()
  @callback recv(term()) :: {:ok, Enumerable.t()} | {:error, term()}
end
```

The five callbacks cover the full gRPC lifecycle used by `GnmiSession`: opening a channel, starting a bidirectional subscribe stream, sending requests, receiving response streams, and disconnecting.

### SshClient Behaviour

Defined in `lib/switch_telemetry/collector/ssh_client.ex`:

```elixir
defmodule SwitchTelemetry.Collector.SshClient do
  @moduledoc "Behaviour wrapping SSH client operations for NETCONF sessions."

  @callback connect(charlist(), integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  @callback session_channel(pid(), integer()) :: {:ok, integer()} | {:error, term()}
  @callback subsystem(pid(), integer(), charlist(), integer()) :: :success | :failure
  @callback send(pid(), integer(), iodata()) :: :ok | {:error, term()}
  @callback close(pid()) :: :ok
end
```

The five callbacks mirror the Erlang `:ssh` and `:ssh_connection` API surface used by `NetconfSession`: connecting, opening a session channel, invoking the NETCONF subsystem, sending XML RPCs, and closing the connection.

### Default Implementations

Each behaviour has a thin wrapper module that delegates to the real library. These are co-located in the same file as their behaviour:

**DefaultGrpcClient** (in `grpc_client.ex`):

```elixir
defmodule SwitchTelemetry.Collector.DefaultGrpcClient do
  @behaviour SwitchTelemetry.Collector.GrpcClient

  @impl true
  def connect(target, opts), do: GRPC.Stub.connect(target, opts)

  @impl true
  def disconnect(channel), do: GRPC.Stub.disconnect(channel)

  @impl true
  def subscribe(channel), do: Gnmi.GNMI.Stub.subscribe(channel)

  @impl true
  def send_request(stream, request), do: GRPC.Stub.send_request(stream, request)

  @impl true
  def recv(stream), do: GRPC.Stub.recv(stream)
end
```

**DefaultSshClient** (in `ssh_client.ex`):

```elixir
defmodule SwitchTelemetry.Collector.DefaultSshClient do
  @behaviour SwitchTelemetry.Collector.SshClient

  @impl true
  def connect(host, port, opts), do: :ssh.connect(host, port, opts)

  @impl true
  def session_channel(ssh_ref, timeout), do: :ssh_connection.session_channel(ssh_ref, timeout)

  @impl true
  def subsystem(ssh_ref, channel_id, subsystem, timeout),
    do: :ssh_connection.subsystem(ssh_ref, channel_id, subsystem, timeout)

  @impl true
  def send(ssh_ref, channel_id, data), do: :ssh_connection.send(ssh_ref, channel_id, data)

  @impl true
  def close(ssh_ref), do: :ssh.close(ssh_ref)
end
```

### The `Application.get_env` Dispatch Pattern

Each session GenServer includes a private helper function that reads the active implementation from application config at runtime. The third argument to `Application.get_env/3` provides the default (the real implementation), so **no configuration is needed in production** -- the behaviour abstraction is invisible outside of tests.

```elixir
# In GnmiSession
defp grpc_client do
  Application.get_env(
    :switch_telemetry,
    :grpc_client,
    SwitchTelemetry.Collector.DefaultGrpcClient
  )
end

# In NetconfSession
defp ssh_client do
  Application.get_env(
    :switch_telemetry,
    :ssh_client,
    SwitchTelemetry.Collector.DefaultSshClient
  )
end
```

Session code then calls `grpc_client().connect(target, [])` or `ssh_client().connect(host, port, opts)` instead of calling `GRPC.Stub.connect/2` or `:ssh.connect/3` directly. This single level of indirection is the only runtime difference from direct calls.

### Mox Mocks in Tests

Mox mocks are defined in `test/support/mocks.ex`:

```elixir
Mox.defmock(SwitchTelemetry.Collector.MockGrpcClient,
  for: SwitchTelemetry.Collector.GrpcClient)

Mox.defmock(SwitchTelemetry.Collector.MockSshClient,
  for: SwitchTelemetry.Collector.SshClient)
```

Tests swap in the mock via `Application.put_env/3` in a setup block and clean up with `on_exit`:

```elixir
setup do
  Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)
  on_exit(fn -> Application.delete_env(:switch_telemetry, :grpc_client) end)
  :ok
end
```

This allows tests to set precise expectations on every external call. For example, testing that `GnmiSession` handles a connection failure:

```elixir
test "failure increments retry_count and schedules retry" do
  device = create_device()
  state = make_state(device, retry_count: 0)

  MockGrpcClient
  |> expect(:connect, fn _target, [] -> {:error, :connection_refused} end)

  {:noreply, new_state} = GnmiSession.handle_info(:connect, state)

  assert new_state.retry_count == 1
  assert new_state.channel == nil
end
```

Tests using these mocks run with `async: false` because `Application.put_env/3` is a global operation. Each test module calls `setup :verify_on_exit!` to ensure all expected mock calls were actually invoked.

> **See also:** [ADR-006: Behaviour Abstractions for Protocol Clients](../decisions/ADR-006-behaviour-abstractions.md) for the full decision record, including alternatives considered and consequences.

## Protocol Comparison

| Feature | gNMI | NETCONF |
|---|---|---|
| Transport | gRPC over HTTP/2 | SSH (port 830) |
| Encoding | Protocol Buffers (binary) | XML |
| Streaming | Native (Subscribe RPC) | RFC 5277 notifications (limited) |
| Performance | High throughput, compact wire format | Higher overhead (XML verbosity) |
| Vendor Support | Growing (all major vendors) | Universal (every managed device) |
| Configuration | Full CRUD via Set RPC | Full CRUD (edit-config, copy-config) |
| Data Models | OpenConfig YANG + vendor YANG | IETF YANG + vendor YANG |
| Best For | Streaming telemetry at scale | Config management, legacy devices |

### When to Use Each

- **gNMI**: Preferred for all streaming telemetry. Use when device supports it. Better performance, native streaming, compact encoding.
- **NETCONF**: Fallback for devices without gNMI support. Also used for configuration backup/restore operations. Required for older device platforms.
- **Both**: Some devices benefit from gNMI for telemetry + NETCONF for config operations.

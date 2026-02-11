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
  """
  use GenServer
  require Logger

  defstruct [:device, :channel, :stream, :task, :retry_count]

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)
    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:gnmi, device.id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    send(self(), :connect)
    {:ok, %__MODULE__{device: device, retry_count: 0}}
  end

  @impl true
  def handle_info(:connect, state) do
    target = "#{state.device.ip_address}:#{state.device.gnmi_port}"

    case GRPC.Stub.connect(target, interceptors: [GRPC.Logger.Client]) do
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
    # Build the SubscribeRequest
    subscriptions = build_subscriptions(state.device)

    subscribe_request = %Gnmi.SubscribeRequest{
      request: {:subscribe, %Gnmi.SubscriptionList{
        subscription: subscriptions,
        mode: :STREAM,
        encoding: :PROTO
      }}
    }

    # Open bidirectional stream
    stream = Gnmi.GNMI.Stub.subscribe(state.channel)

    # Send the subscription request
    GRPC.Stub.send_request(stream, subscribe_request)

    # Spawn a task to read responses (non-blocking)
    task = Task.async(fn -> read_stream(stream, state.device) end)

    {:noreply, %{state | stream: stream, task: task}}
  end

  def handle_info({ref, :stream_ended}, state) when ref == state.task.ref do
    Process.demonitor(ref, [:flush])
    Logger.warning("gNMI stream ended for #{state.device.hostname}, reconnecting")
    schedule_retry(state)
    {:noreply, %{state | stream: nil, task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when ref == state.task.ref do
    Logger.error("gNMI stream task crashed for #{state.device.hostname}: #{inspect(reason)}")
    schedule_retry(state)
    {:noreply, %{state | stream: nil, task: nil}}
  end

  # --- Private ---

  defp read_stream(stream, device) do
    {:ok, response_stream} = GRPC.Stub.recv(stream)

    response_stream
    |> Stream.each(fn
      {:ok, %Gnmi.SubscribeResponse{response: {:update, notification}}} ->
        metrics = parse_notification(device, notification)
        SwitchTelemetry.Metrics.insert_batch(metrics)

        Phoenix.PubSub.broadcast(
          SwitchTelemetry.PubSub,
          "device:#{device.id}",
          {:gnmi_metrics, device.id, metrics}
        )

      {:ok, %Gnmi.SubscribeResponse{response: {:sync_response, true}}} ->
        Logger.debug("gNMI sync complete for #{device.hostname}")

      {:error, reason} ->
        Logger.error("gNMI stream error for #{device.hostname}: #{inspect(reason)}")
    end)
    |> Stream.run()

    :stream_ended
  end

  defp parse_notification(device, %Gnmi.Notification{} = notif) do
    timestamp = DateTime.from_unix!(notif.timestamp, :nanosecond)

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
    parts = if prefix, do: prefix.elem ++ elems, else: elems

    "/" <> Enum.map_join(parts, "/", fn %Gnmi.PathElem{name: name, key: keys} ->
      if map_size(keys) > 0 do
        key_str = Enum.map_join(keys, ",", fn {k, v} -> "#{k}=#{v}" end)
        "#{name}[#{key_str}]"
      else
        name
      end
    end)
  end

  defp extract_float(%Gnmi.TypedValue{value: {:float_val, v}}), do: v
  defp extract_float(%Gnmi.TypedValue{value: {:double_val, v}}), do: v
  defp extract_float(_), do: nil

  defp extract_int(%Gnmi.TypedValue{value: {:int_val, v}}), do: v
  defp extract_int(%Gnmi.TypedValue{value: {:uint_val, v}}), do: v
  defp extract_int(_), do: nil

  defp extract_str(%Gnmi.TypedValue{value: {:string_val, v}}), do: v
  defp extract_str(%Gnmi.TypedValue{value: {:json_val, v}}), do: v
  defp extract_str(_), do: nil

  defp extract_tags(%Gnmi.Path{elem: elems}) do
    Enum.reduce(elems, %{}, fn %Gnmi.PathElem{key: keys}, acc ->
      Map.merge(acc, keys)
    end)
  end

  defp build_subscriptions(device) do
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
        case Regex.run(~r/^(.+)\[(.+)\]$/, segment) do
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
    delay = min(:timer.seconds(5) * :math.pow(2, state.retry_count), :timer.minutes(5))
    Process.send_after(self(), :connect, trunc(delay))
  end
end
```

## NETCONF (Network Configuration Protocol)

### Overview

NETCONF (RFC 6241) is an XML-based network management protocol that runs over SSH. It's universally supported across network vendors and is the primary protocol for devices that don't support gNMI.

### Erlang SSH for NETCONF

There is no production-ready NETCONF client library for Elixir. We build one using Erlang's `:ssh` application, which provides SSH client functionality including subsystem invocation.

```elixir
defmodule SwitchTelemetry.Collector.NetconfSession do
  @moduledoc """
  Manages a NETCONF session to a network device over SSH.
  Uses Erlang :ssh for transport and SweetXml for XML parsing.
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

  defstruct [:device, :ssh_ref, :channel_id, :buffer, :message_id, :pending_requests]

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)
    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:netconf, device.id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    send(self(), :connect)

    {:ok, %__MODULE__{
      device: device,
      buffer: "",
      message_id: 1,
      pending_requests: %{}
    }}
  end

  @impl true
  def handle_info(:connect, state) do
    device = state.device
    credential = SwitchTelemetry.Devices.get_credential!(device.credentials_id)

    ssh_opts = [
      {:user, String.to_charlist(credential.username)},
      {:password, String.to_charlist(credential.password)},
      {:silently_accept_hosts, true},
      {:connect_timeout, 10_000}
    ]

    with {:ok, ssh_ref} <- :ssh.connect(
           String.to_charlist(device.ip_address),
           device.netconf_port,
           ssh_opts
         ),
         {:ok, channel_id} <- :ssh_connection.session_channel(ssh_ref, 30_000),
         :success <- :ssh_connection.subsystem(ssh_ref, channel_id, ~c"netconf", 30_000) do

      Logger.info("NETCONF connected to #{device.hostname}")

      # Send our hello
      :ssh_connection.send(ssh_ref, channel_id, @netconf_hello)

      # Schedule periodic collection
      interval = device.collection_interval_ms || 30_000
      :timer.send_interval(interval, :collect)

      {:noreply, %{state | ssh_ref: ssh_ref, channel_id: channel_id}}
    else
      error ->
        Logger.error("NETCONF connection failed for #{device.hostname}: #{inspect(error)}")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, state}
    end
  end

  def handle_info(:collect, state) do
    paths = SwitchTelemetry.Collector.Subscriptions.paths_for_device(state.device)

    Enum.each(paths, fn path ->
      rpc = build_get_rpc(state.message_id, path)
      :ssh_connection.send(state.ssh_ref, state.channel_id, rpc)
    end)

    {:noreply, %{state | message_id: state.message_id + length(paths)}}
  end

  # Receive SSH data
  def handle_info({:ssh_cm, _ref, {:data, _channel, _type, data}}, state) do
    buffer = state.buffer <> to_string(data)

    case String.split(buffer, @framing_end, parts: 2) do
      [complete_msg, rest] ->
        handle_netconf_message(complete_msg, state)
        {:noreply, %{state | buffer: rest}}

      [_incomplete] ->
        {:noreply, %{state | buffer: buffer}}
    end
  end

  def handle_info({:ssh_cm, _ref, {:closed, _channel}}, state) do
    Logger.warning("NETCONF session closed for #{state.device.hostname}, reconnecting")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | ssh_ref: nil, channel_id: nil}}
  end

  # --- Private ---

  defp handle_netconf_message(xml, state) do
    metrics = parse_netconf_response(xml, state.device)

    if metrics != [] do
      SwitchTelemetry.Metrics.insert_batch(metrics)

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{state.device.id}",
        {:netconf_metrics, state.device.id, metrics}
      )
    end
  end

  defp parse_netconf_response(xml, device) do
    now = DateTime.utc_now()

    xml
    |> xpath(~x"//rpc-reply/data//*[text()]"l)
    |> Enum.map(fn element ->
      path = xpath(element, ~x"."e) |> element_to_path()
      value = xpath(element, ~x"./text()"s)

      %{
        time: now,
        device_id: device.id,
        path: path,
        source: "netconf",
        tags: %{},
        value_float: parse_float(value),
        value_int: parse_int(value),
        value_str: if(is_numeric?(value), do: nil, else: value)
      }
    end)
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
    # Convert XML element path to XPath-like string
    # Implementation depends on YANG model structure
    "/" <> (SweetXml.xpath(element, ~x"ancestor-or-self::*"l)
    |> Enum.map(fn e -> SweetXml.xpath(e, ~x"local-name()"s) end)
    |> Enum.join("/"))
  end

  defp parse_float(val) do
    case Float.parse(val) do
      {f, ""} -> f
      _ -> nil
    end
  end

  defp parse_int(val) do
    case Integer.parse(val) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp is_numeric?(val), do: parse_float(val) != nil or parse_int(val) != nil
end
```

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

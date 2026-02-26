defmodule SwitchTelemetry.Collector.GnmiSession do
  @moduledoc """
  GenServer managing a single gNMI streaming subscription to a network device.

  Each device gets one GnmiSession that:
  1. Opens a gRPC channel to the device
  2. Sends a SubscribeRequest with paths from the database
  3. Reads the bidirectional stream in a linked Task
  4. Parses gNMI Notifications into metrics
  5. Inserts metrics to InfluxDB and broadcasts via PubSub
  6. Reconnects with exponential backoff on failure
  """
  use GenServer
  require Logger

  alias SwitchTelemetry.Collector.{Helpers, StreamMonitor, Subscription, TlsHelper}

  @connect_timeout 10_000
  @watchdog_interval :timer.seconds(90)
  @max_stale_reconnects 3

  defstruct [
    :device,
    :channel,
    :stream,
    :task_ref,
    :task_pid,
    :retry_count,
    :credential,
    :connected_at,
    :watchdog_ref,
    stale_reconnects: 0
  ]

  # --- Public API ---

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)

    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:gnmi, device.id}}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def stop(device_id) do
    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:gnmi, device_id}}}

    GenServer.stop(name)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    Logger.metadata(gnmi_device: device.hostname)
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{device: device, retry_count: 0}}
  end

  @impl true
  def handle_info(:connect, state) do
    target = "#{state.device.ip_address}:#{state.device.gnmi_port}"
    credential = Helpers.load_credential(state.device)
    grpc_opts = TlsHelper.build_grpc_opts(state.device.secure_mode, credential)
    grpc_opts = Keyword.merge(grpc_opts, adapter_opts: [connect_timeout: @connect_timeout])

    case Helpers.grpc_client().connect(target, grpc_opts) do
      {:ok, channel} ->
        Logger.info("connected to #{target}")

        SwitchTelemetry.Devices.update_device(state.device, %{
          status: :active,
          last_seen_at: DateTime.utc_now()
        })

        StreamMonitor.report_connected(state.device.id, :gnmi)
        send(self(), :subscribe)

        {:noreply,
         %{
           state
           | channel: channel,
             retry_count: 0,
             credential: credential,
             connected_at: System.monotonic_time(:second)
         }}

      {:error, reason} ->
        Logger.warning("connection failed: #{inspect(reason)}")

        SwitchTelemetry.Devices.update_device(state.device, %{status: :unreachable})
        StreamMonitor.report_disconnected(state.device.id, :gnmi, reason)
        schedule_retry(state)
        {:noreply, %{state | retry_count: state.retry_count + 1}}
    end
  end

  def handle_info(:subscribe, state) do
    subscriptions = build_subscriptions(state.device)

    Logger.info("subscribing #{length(subscriptions)} paths")

    encoding = encoding_to_gnmi(state.device.gnmi_encoding)

    subscribe_request = %Gnmi.SubscribeRequest{
      request:
        {:subscribe,
         %Gnmi.SubscriptionList{
           subscription: subscriptions,
           mode: :STREAM,
           encoding: encoding
         }}
    }

    stream = Helpers.grpc_client().subscribe(state.channel)
    Helpers.grpc_client().send_request(stream, subscribe_request)

    task = Task.async(fn -> read_stream(stream, state.device) end)
    watchdog_ref = Process.send_after(self(), :watchdog_check, @watchdog_interval)

    {:noreply,
     %{state | stream: stream, task_ref: task.ref, task_pid: task.pid, watchdog_ref: watchdog_ref}}
  end

  def handle_info(:watchdog_check, %{task_pid: pid} = state) when is_pid(pid) do
    stream_status = StreamMonitor.get_stream(state.device.id, :gnmi)

    if stream_status && stream_status.message_count > 0 do
      Logger.debug("gnmi_rx: watchdog healthy msg_count=#{stream_status.message_count}")
      ref = Process.send_after(self(), :watchdog_check, @watchdog_interval)
      {:noreply, %{state | stale_reconnects: 0, watchdog_ref: ref}}
    else
      Logger.warning("watchdog: no data received, killing stream task")
      Process.exit(pid, :watchdog_timeout)
      {:noreply, %{state | watchdog_ref: nil}}
    end
  end

  def handle_info(:watchdog_check, state) do
    {:noreply, %{state | watchdog_ref: nil}}
  end

  # Stream task killed by watchdog — three-strike escalation
  def handle_info({:DOWN, ref, :process, _pid, :watchdog_timeout}, %{task_ref: ref} = state) do
    strikes = state.stale_reconnects + 1

    if strikes >= @max_stale_reconnects do
      Logger.error("watchdog: #{strikes} consecutive stale streams, stopping for Horde restart")
      {:stop, :normal, cancel_watchdog(%{state | stale_reconnects: strikes})}
    else
      Logger.warning("watchdog: stale strike #{strikes}/#{@max_stale_reconnects}, reconnecting")
      delay = Helpers.retry_delay(strikes)
      Process.send_after(self(), :connect, delay)

      {:noreply,
       %{
         state
         | stream: nil,
           task_ref: nil,
           task_pid: nil,
           watchdog_ref: nil,
           stale_reconnects: strikes
       }}
    end
  end

  # Stream task completed normally (stream ended)
  def handle_info({ref, :stream_ended}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    uptime = format_uptime(state.connected_at)
    Logger.warning("stream ended after #{uptime}, reconnecting (retry #{state.retry_count + 1})")
    StreamMonitor.report_disconnected(state.device.id, :gnmi, :stream_ended)
    schedule_retry(state)

    {:noreply,
     cancel_watchdog(%{state | stream: nil, task_ref: nil, task_pid: nil, connected_at: nil})}
  end

  # Stream task killed by code purge during development recompilation.
  # The gRPC channel is still alive — just resubscribe immediately.
  def handle_info({:DOWN, ref, :process, _pid, :killed}, %{task_ref: ref, channel: ch} = state)
      when ch != nil do
    Logger.info("stream reader restarting (code reload)")
    send(self(), :subscribe)
    {:noreply, cancel_watchdog(%{state | stream: nil, task_ref: nil, task_pid: nil})}
  end

  # Stream task crashed for other reasons — full reconnect with backoff
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    uptime = format_uptime(state.connected_at)
    Logger.error("stream task crashed after #{uptime}: #{inspect(reason, limit: 200)}")
    StreamMonitor.report_disconnected(state.device.id, :gnmi, reason)
    schedule_retry(state)

    {:noreply,
     cancel_watchdog(%{state | stream: nil, task_ref: nil, task_pid: nil, connected_at: nil})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    uptime = format_uptime(state.connected_at)
    Logger.info("terminating reason=#{inspect(reason)} uptime=#{uptime}")
    StreamMonitor.report_disconnected(state.device.id, :gnmi, :terminated)

    if state.channel do
      Helpers.grpc_client().disconnect(state.channel)
    end

    :ok
  end

  # --- Private ---

  defp read_stream(stream, device) do
    case Helpers.grpc_client().recv(stream) do
      {:ok, response_stream} ->
        Logger.debug("gnmi_rx: recv returned stream, starting iteration")

        response_stream
        |> Stream.each(fn
          {:ok, %Gnmi.SubscribeResponse{response: {:update, notification}}} ->
            path_count = length(notification.update || [])
            Logger.debug("gnmi_rx: update path_count=#{path_count}")
            metrics = parse_notification(device, notification)
            Helpers.persist_and_broadcast(metrics, device.id, :gnmi)

          {:ok, %Gnmi.SubscribeResponse{response: {:sync_response, true}}} ->
            Logger.debug("sync complete")

          {:error, reason} ->
            Logger.error("stream error: #{inspect(reason)}")
            StreamMonitor.report_error(device.id, :gnmi, reason)

          other ->
            Logger.warning("gnmi_rx: unmatched response: #{inspect(other, limit: 200)}")
        end)
        |> Stream.run()

      {:error, reason} ->
        Logger.error("recv failed: #{inspect(reason)}")
    end

    :stream_ended
  end

  defp parse_notification(device, %Gnmi.Notification{} = notif) do
    timestamp =
      case notif.timestamp do
        ts when is_integer(ts) and ts > 0 ->
          DateTime.from_unix!(ts, :nanosecond)

        _ ->
          DateTime.utc_now()
      end

    Enum.map(notif.update, fn %Gnmi.Update{path: path, val: typed_val} ->
      formatted_path = format_path(notif.prefix, path)
      value_float = extract_float(typed_val)
      value_int = extract_int(typed_val)
      value_str = extract_str(typed_val)

      if is_nil(value_float) and is_nil(value_int) and is_nil(value_str) do
        warn_once(
          :extract_nil,
          "value extraction failed path=#{formatted_path} typed_value=#{inspect_short(typed_val)}"
        )
      end

      %{
        time: timestamp,
        device_id: device.id,
        path: formatted_path,
        source: "gnmi",
        tags: extract_tags(path),
        value_float: value_float,
        value_int: value_int,
        value_str: value_str
      }
    end)
  end

  defp format_path(prefix, %Gnmi.Path{elem: elems}) do
    prefix_elems = if prefix, do: prefix.elem || [], else: []
    all_elems = prefix_elems ++ (elems || [])

    "/" <>
      Enum.map_join(all_elems, "/", fn %Gnmi.PathElem{name: name, key: keys} ->
        if keys != nil and map_size(keys) > 0 do
          key_str = Enum.map_join(keys, ",", fn {k, v} -> "#{k}=#{v}" end)
          "#{name}[#{key_str}]"
        else
          name
        end
      end)
  end

  defp format_path(_prefix, _path), do: "/"

  defp extract_tags(%Gnmi.Path{elem: elems}) when is_list(elems) do
    Enum.reduce(elems, %{}, fn %Gnmi.PathElem{key: keys}, acc ->
      if keys != nil, do: Map.merge(acc, keys), else: acc
    end)
  end

  defp extract_tags(_), do: %{}

  defp extract_float(%Gnmi.TypedValue{value: {:double_val, v}}), do: v
  defp extract_float(%Gnmi.TypedValue{value: {:float_val, v}}), do: v
  defp extract_float(%Gnmi.TypedValue{value: {:int_val, v}}), do: v / 1
  defp extract_float(%Gnmi.TypedValue{value: {:uint_val, v}}), do: v / 1

  defp extract_float(%Gnmi.TypedValue{value: {encoding, bytes}})
       when encoding in [:json_ietf_val, :json_val] do
    case decode_json_value(bytes) do
      v when is_float(v) -> v
      v when is_integer(v) -> v / 1
      v when is_binary(v) -> parse_number_string(v)
      _ -> nil
    end
  end

  defp extract_float(_), do: nil

  defp extract_int(%Gnmi.TypedValue{value: {:int_val, v}}), do: v
  defp extract_int(%Gnmi.TypedValue{value: {:uint_val, v}}), do: v

  defp extract_int(%Gnmi.TypedValue{value: {encoding, bytes}})
       when encoding in [:json_ietf_val, :json_val] do
    case decode_json_value(bytes) do
      v when is_integer(v) -> v
      v when is_binary(v) -> parse_integer_string(v)
      _ -> nil
    end
  end

  defp extract_int(_), do: nil

  defp extract_str(%Gnmi.TypedValue{value: {:string_val, v}}), do: v

  defp extract_str(%Gnmi.TypedValue{value: {encoding, bytes}})
       when encoding in [:json_ietf_val, :json_val] do
    case decode_json_value(bytes) do
      v when is_binary(v) -> v
      v when is_map(v) -> Jason.encode!(v)
      _ -> nil
    end
  end

  defp extract_str(_), do: nil

  # RFC 7951: YANG uint64/int64 are encoded as JSON strings to avoid precision loss.
  # Cisco IOS-XE sends counter values like "12345678" (quoted) in JSON_IETF encoding.
  defp parse_number_string(s) do
    case Float.parse(s) do
      {v, ""} -> v
      _ -> nil
    end
  end

  defp parse_integer_string(s) do
    case Integer.parse(s) do
      {v, ""} -> v
      _ -> nil
    end
  end

  defp decode_json_value(bytes) when is_binary(bytes) do
    case Jason.decode(bytes) do
      {:ok, val} ->
        val

      {:error, reason} ->
        warn_once(
          :json_fail,
          "JSON decode failed: #{inspect(reason)} bytes=#{inspect_short(bytes, 80)}"
        )

        nil
    end
  end

  defp decode_json_value(_), do: nil

  defp encoding_to_gnmi(:json_ietf), do: :JSON_IETF
  defp encoding_to_gnmi(:json), do: :JSON
  defp encoding_to_gnmi(:proto), do: :PROTO
  defp encoding_to_gnmi(_), do: :PROTO

  defp build_subscriptions(device) do
    import Ecto.Query

    subs =
      from(s in Subscription,
        where: s.device_id == ^device.id and s.enabled == true,
        select: s
      )
      |> SwitchTelemetry.Repo.all()

    Enum.flat_map(subs, fn sub ->
      Enum.map(sub.paths, fn path_str ->
        %Gnmi.Subscription{
          path: %Gnmi.Path{
            elem: parse_path_string(path_str)
          },
          mode: :SAMPLE,
          sample_interval: sub.sample_interval_ns
        }
      end)
    end)
  end

  defp parse_path_string(path_str) do
    path_str
    |> String.trim_leading("/")
    |> String.split("/")
    |> Enum.map(fn segment ->
      case Regex.run(~r/^([^\[]+)\[(.+)\]$/, segment) do
        [_, name, keys_str] ->
          keys =
            keys_str
            |> String.split(",")
            |> Map.new(fn kv ->
              [k, v] = String.split(kv, "=", parts: 2)
              {k, v}
            end)

          %Gnmi.PathElem{name: name, key: keys}

        nil ->
          %Gnmi.PathElem{name: segment, key: %{}}
      end
    end)
  end

  defp cancel_watchdog(%{watchdog_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | watchdog_ref: nil}
  end

  defp cancel_watchdog(state), do: state

  defp schedule_retry(state) do
    delay = Helpers.retry_delay(state.retry_count)
    Logger.info("retry #{state.retry_count + 1} in #{div(delay, 1000)}s")
    Process.send_after(self(), :connect, delay)
  end

  defp format_uptime(nil), do: "n/a"

  defp format_uptime(started_at) do
    secs = System.monotonic_time(:second) - started_at

    cond do
      secs < 60 -> "#{secs}s"
      secs < 3600 -> "#{div(secs, 60)}m#{rem(secs, 60)}s"
      true -> "#{div(secs, 3600)}h#{div(rem(secs, 3600), 60)}m"
    end
  end

  # Log first occurrence, then every 100th, with suppressed count
  defp warn_once(key, message) do
    count = Process.get(key, 0)

    cond do
      count == 0 -> Logger.warning(message)
      rem(count, 100) == 0 -> Logger.warning("#{message} (repeated #{count}x)")
      true -> :ok
    end

    Process.put(key, count + 1)
  end

  defp inspect_short(term, limit \\ 120) do
    s = inspect(term, limit: 3, printable_limit: 80)
    if String.length(s) > limit, do: String.slice(s, 0, limit) <> "...", else: s
  end
end

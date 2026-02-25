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

  alias SwitchTelemetry.{Devices, Metrics}
  alias SwitchTelemetry.Collector.{StreamMonitor, Subscription, TlsHelper}

  @max_retry_delay :timer.minutes(5)
  @base_retry_delay :timer.seconds(5)
  @connect_timeout 10_000

  defstruct [:device, :channel, :stream, :task_ref, :retry_count, :credential]

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
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{device: device, retry_count: 0}}
  end

  @impl true
  def handle_info(:connect, state) do
    target = "#{state.device.ip_address}:#{state.device.gnmi_port}"
    credential = load_credential(state.device)
    grpc_opts = TlsHelper.build_grpc_opts(state.device.secure_mode, credential)
    grpc_opts = Keyword.merge(grpc_opts, adapter_opts: [connect_timeout: @connect_timeout])

    case grpc_client().connect(target, grpc_opts) do
      {:ok, channel} ->
        Logger.info("gNMI connected to #{state.device.hostname} at #{target}")

        Devices.update_device(state.device, %{
          status: :active,
          last_seen_at: DateTime.utc_now()
        })

        StreamMonitor.report_connected(state.device.id, :gnmi)
        send(self(), :subscribe)
        {:noreply, %{state | channel: channel, retry_count: 0, credential: credential}}

      {:error, reason} ->
        Logger.warning("gNMI connection to #{state.device.hostname} failed: #{inspect(reason)}")

        Devices.update_device(state.device, %{status: :unreachable})
        StreamMonitor.report_disconnected(state.device.id, :gnmi, reason)
        schedule_retry(state)
        {:noreply, %{state | retry_count: state.retry_count + 1}}
    end
  end

  def handle_info(:subscribe, state) do
    subscriptions = build_subscriptions(state.device)

    Logger.info(
      "gNMI subscribing for #{state.device.hostname}: #{length(subscriptions)} subscription paths"
    )

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

    stream = grpc_client().subscribe(state.channel)
    grpc_client().send_request(stream, subscribe_request)

    task = Task.async(fn -> read_stream(stream, state.device) end)

    {:noreply, %{state | stream: stream, task_ref: task.ref}}
  end

  # Stream task completed normally (stream ended)
  def handle_info({ref, :stream_ended}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    Logger.warning("gNMI stream ended for #{state.device.hostname}, reconnecting")
    StreamMonitor.report_disconnected(state.device.id, :gnmi, :stream_ended)
    schedule_retry(state)
    {:noreply, %{state | stream: nil, task_ref: nil}}
  end

  # Stream task killed by code purge during development recompilation.
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
    StreamMonitor.report_disconnected(state.device.id, :gnmi, reason)
    schedule_retry(state)
    {:noreply, %{state | stream: nil, task_ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    StreamMonitor.report_disconnected(state.device.id, :gnmi, :terminated)

    if state.channel do
      grpc_client().disconnect(state.channel)
    end

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
              Metrics.insert_batch(metrics)

              Phoenix.PubSub.broadcast(
                SwitchTelemetry.PubSub,
                "device:#{device.id}",
                {:gnmi_metrics, device.id, metrics}
              )

              StreamMonitor.report_message(device.id, :gnmi)
            end

          {:ok, %Gnmi.SubscribeResponse{response: {:sync_response, true}}} ->
            Logger.debug("gNMI sync complete for #{device.hostname}")

          {:error, reason} ->
            Logger.error("gNMI stream error for #{device.hostname}: #{inspect(reason)}")
            StreamMonitor.report_error(device.id, :gnmi, reason)
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
        Logger.warning(
          "gNMI value extraction failed for #{device.hostname} path=#{formatted_path} " <>
            "typed_value=#{inspect(typed_val)}"
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
        Logger.warning("gNMI JSON decode failed: #{inspect(reason)} bytes=#{inspect(bytes)}")
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

  defp schedule_retry(state) do
    delay =
      min(
        trunc(@base_retry_delay * :math.pow(2, state.retry_count)),
        @max_retry_delay
      )

    Process.send_after(self(), :connect, delay)
  end

  defp load_credential(device) do
    if device.credential_id do
      try do
        Devices.get_credential!(device.credential_id)
      rescue
        Ecto.NoResultsError -> nil
      end
    else
      nil
    end
  end

  defp grpc_client do
    Application.get_env(
      :switch_telemetry,
      :grpc_client,
      SwitchTelemetry.Collector.DefaultGrpcClient
    )
  end
end

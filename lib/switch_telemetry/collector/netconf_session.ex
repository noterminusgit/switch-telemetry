defmodule SwitchTelemetry.Collector.NetconfSession do
  @moduledoc """
  GenServer managing a NETCONF-over-SSH session to a network device.

  Uses Erlang :ssh to connect on port 830 and exchange XML RPCs.
  Periodically collects metrics via <get> RPCs with subtree filters.
  Parses XML responses with SweetXml and inserts metrics to InfluxDB.
  """
  use GenServer
  require Logger
  import SweetXml

  alias SwitchTelemetry.Devices
  alias SwitchTelemetry.Collector.{Helpers, StreamMonitor, Subscription}

  @framing_end "]]>]]>"
  @connect_timeout 10_000
  @channel_timeout 30_000

  @netconf_hello """
  <?xml version="1.0" encoding="UTF-8"?>
  <hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
    <capabilities>
      <capability>urn:ietf:params:netconf:base:1.0</capability>
      <capability>urn:ietf:params:netconf:base:1.1</capability>
    </capabilities>
  </hello>]]>]]>
  """

  defstruct [
    :device,
    :ssh_ref,
    :channel_id,
    :timer_ref,
    :connected_at,
    buffer: "",
    message_id: 1,
    retry_count: 0
  ]

  # --- Public API ---

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)

    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:netconf, device.id}}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def stop(device_id) do
    name = {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:netconf, device_id}}}

    GenServer.stop(name)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    Logger.metadata(netconf_device: device.hostname)
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %__MODULE__{device: device}}
  end

  @impl true
  def handle_info(:connect, state) do
    device = state.device

    case Helpers.load_credential(device) do
      nil ->
        Logger.error("no credential, retry #{state.retry_count + 1}")
        Devices.update_device(device, %{status: :unreachable})
        StreamMonitor.report_disconnected(device.id, :netconf, :no_credential)
        delay = Helpers.retry_delay(state.retry_count)
        Logger.info("retry #{state.retry_count + 1} in #{div(delay, 1000)}s")
        Process.send_after(self(), :connect, delay)
        {:noreply, %{state | retry_count: state.retry_count + 1}}

      credential ->
        do_connect(state, device, credential)
    end
  end

  def handle_info(:collect, %{ssh_ref: nil} = state), do: {:noreply, state}

  def handle_info(:collect, state) do
    paths = get_subscription_paths(state.device)

    state =
      Enum.reduce(paths, state, fn path, acc ->
        rpc = build_get_rpc(acc.message_id, path)
        Helpers.ssh_client().send(acc.ssh_ref, acc.channel_id, rpc)
        %{acc | message_id: acc.message_id + 1}
      end)

    {:noreply, state}
  end

  def handle_info({:ssh_cm, _ref, {:data, _channel, _type, data}}, state) do
    buffer = state.buffer <> to_string(data)

    {messages, remaining} = extract_messages(buffer)

    Enum.each(messages, fn msg ->
      handle_netconf_message(msg, state.device)
    end)

    {:noreply, %{state | buffer: remaining}}
  end

  def handle_info({:ssh_cm, _ref, {:closed, _channel}}, state) do
    uptime = format_uptime(state.connected_at)

    Logger.warning(
      "session closed after #{uptime}, reconnecting (retry #{state.retry_count + 1})"
    )

    StreamMonitor.report_disconnected(state.device.id, :netconf, :channel_closed)
    cleanup_ssh(state)
    delay = Helpers.retry_delay(state.retry_count)
    Logger.info("retry #{state.retry_count + 1} in #{div(delay, 1000)}s")
    Process.send_after(self(), :connect, delay)

    {:noreply,
     %{
       state
       | ssh_ref: nil,
         channel_id: nil,
         buffer: "",
         retry_count: state.retry_count + 1,
         connected_at: nil
     }}
  end

  def handle_info({:ssh_cm, _ref, {:exit_status, _channel, _status}}, state) do
    {:noreply, state}
  end

  def handle_info({:ssh_cm, _ref, {:eof, _channel}}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    uptime = format_uptime(state.connected_at)
    Logger.info("terminating reason=#{inspect(reason)} uptime=#{uptime}")
    StreamMonitor.report_disconnected(state.device.id, :netconf, :terminated)
    cleanup_ssh(state)
    :ok
  end

  # --- Private ---

  defp do_connect(state, device, credential) do
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
           Helpers.ssh_client().connect(
             String.to_charlist(device.ip_address),
             device.netconf_port,
             ssh_opts
           ),
         {:ok, channel_id} <-
           Helpers.ssh_client().session_channel(ssh_ref, @channel_timeout),
         :success <-
           Helpers.ssh_client().subsystem(ssh_ref, channel_id, ~c"netconf", @channel_timeout) do
      Logger.info("NETCONF connected to #{device.hostname}")
      Helpers.ssh_client().send(ssh_ref, channel_id, @netconf_hello)

      Devices.update_device(device, %{
        status: :active,
        last_seen_at: DateTime.utc_now()
      })

      StreamMonitor.report_connected(device.id, :netconf)
      interval = device.collection_interval_ms || 30_000
      {:ok, timer_ref} = :timer.send_interval(interval, :collect)

      {:noreply,
       %{
         state
         | ssh_ref: ssh_ref,
           channel_id: channel_id,
           timer_ref: timer_ref,
           retry_count: 0,
           connected_at: System.monotonic_time(:second)
       }}
    else
      error ->
        Logger.error("connection failed: #{inspect(error)}")
        Devices.update_device(device, %{status: :unreachable})
        StreamMonitor.report_disconnected(device.id, :netconf, error)
        delay = Helpers.retry_delay(state.retry_count)
        Logger.info("retry #{state.retry_count + 1} in #{div(delay, 1000)}s")
        Process.send_after(self(), :connect, delay)
        {:noreply, %{state | retry_count: state.retry_count + 1}}
    end
  end

  defp extract_messages(buffer) do
    extract_messages(buffer, [])
  end

  defp extract_messages(buffer, acc) do
    case String.split(buffer, @framing_end, parts: 2) do
      [complete, rest] ->
        extract_messages(rest, [complete | acc])

      [incomplete] ->
        {Enum.reverse(acc), incomplete}
    end
  end

  defp handle_netconf_message(xml, device) do
    metrics = parse_netconf_response(xml, device)
    Helpers.persist_and_broadcast(metrics, device.id, :netconf)
  rescue
    e ->
      Logger.error("NETCONF parse error for #{device.hostname}: #{inspect(e)}")
      StreamMonitor.report_error(device.id, :netconf, e)
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

  defp element_to_path(element) do
    name = xpath(element, ~x"local-name(.)"s)
    "/" <> name
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {f, ""} -> f
      {f, _} -> if String.contains?(value, "."), do: f, else: nil
      :error -> nil
    end
  end

  defp parse_int(value) do
    case Integer.parse(value) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp numeric?(value) do
    parse_float(value) != nil or parse_int(value) != nil
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

  defp get_subscription_paths(device) do
    import Ecto.Query

    from(s in Subscription,
      where: s.device_id == ^device.id and s.enabled == true,
      select: s.paths
    )
    |> SwitchTelemetry.Repo.all()
    |> List.flatten()
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

  defp cleanup_ssh(state) do
    if state.timer_ref do
      :timer.cancel(state.timer_ref)
    end

    if state.ssh_ref do
      Helpers.ssh_client().close(state.ssh_ref)
    end
  end
end

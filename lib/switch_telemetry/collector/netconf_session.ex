defmodule SwitchTelemetry.Collector.NetconfSession do
  @moduledoc """
  GenServer managing a NETCONF-over-SSH session to a network device.

  Uses Erlang :ssh to connect on port 830 and exchange XML RPCs.
  Periodically collects metrics via <get> RPCs with subtree filters.
  Parses XML responses with SweetXml and inserts metrics to TimescaleDB.
  """
  use GenServer
  require Logger
  import SweetXml

  alias SwitchTelemetry.{Devices, Metrics}
  alias SwitchTelemetry.Collector.Subscription

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

  defstruct [:device, :ssh_ref, :channel_id, :timer_ref, buffer: "", message_id: 1]

  # --- Public API ---

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)

    name =
      {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:netconf, device.id}}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def stop(device_id) do
    name =
      {:via, Horde.Registry, {SwitchTelemetry.DistributedRegistry, {:netconf, device_id}}}

    GenServer.stop(name)
  end

  # --- Callbacks ---

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
    credential = Devices.get_credential!(device.credential_id)

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
           :ssh.connect(
             String.to_charlist(device.ip_address),
             device.netconf_port,
             ssh_opts
           ),
         {:ok, channel_id} <-
           :ssh_connection.session_channel(ssh_ref, @channel_timeout),
         :success <-
           :ssh_connection.subsystem(ssh_ref, channel_id, ~c"netconf", @channel_timeout) do
      Logger.info("NETCONF connected to #{device.hostname}")
      :ssh_connection.send(ssh_ref, channel_id, @netconf_hello)

      Devices.update_device(device, %{
        status: :active,
        last_seen_at: DateTime.utc_now()
      })

      interval = device.collection_interval_ms || 30_000
      {:ok, timer_ref} = :timer.send_interval(interval, :collect)

      {:noreply, %{state | ssh_ref: ssh_ref, channel_id: channel_id, timer_ref: timer_ref}}
    else
      error ->
        Logger.error("NETCONF connection to #{device.hostname} failed: #{inspect(error)}")
        Devices.update_device(device, %{status: :unreachable})
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
        :ssh_connection.send(acc.ssh_ref, acc.channel_id, rpc)
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
    Logger.warning("NETCONF session closed for #{state.device.hostname}, reconnecting")
    cleanup_ssh(state)
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | ssh_ref: nil, channel_id: nil, buffer: ""}}
  end

  def handle_info({:ssh_cm, _ref, {:exit_status, _channel, _status}}, state) do
    {:noreply, state}
  end

  def handle_info({:ssh_cm, _ref, {:eof, _channel}}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup_ssh(state)
    :ok
  end

  # --- Private ---

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

    if metrics != [] do
      Metrics.insert_batch(metrics)

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

  defp cleanup_ssh(state) do
    if state.timer_ref do
      :timer.cancel(state.timer_ref)
    end

    if state.ssh_ref do
      :ssh.close(state.ssh_ref)
    end
  end
end

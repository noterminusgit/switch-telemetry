defmodule SwitchTelemetryWeb.StreamLive.Monitor do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Collector.StreamMonitor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      StreamMonitor.subscribe()
    end

    streams = StreamMonitor.list_streams()

    {:ok,
     assign(socket,
       streams: streams,
       page_title: "Stream Monitor",
       filter_protocol: nil,
       filter_state: nil
     )}
  end

  @impl true
  def handle_info({:stream_update, status}, socket) do
    streams = update_stream_in_list(socket.assigns.streams, status)
    {:noreply, assign(socket, streams: filter_streams(streams, socket.assigns))}
  end

  def handle_info({:streams_full, streams}, socket) do
    {:noreply, assign(socket, streams: filter_streams(streams, socket.assigns))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter_protocol", %{"protocol" => ""}, socket) do
    streams = StreamMonitor.list_streams()

    {:noreply,
     assign(socket,
       streams: filter_streams(streams, %{socket.assigns | filter_protocol: nil}),
       filter_protocol: nil
     )}
  end

  def handle_event("filter_protocol", %{"protocol" => protocol}, socket) do
    streams = StreamMonitor.list_streams()
    filter_protocol = String.to_existing_atom(protocol)

    {:noreply,
     assign(socket,
       streams: filter_streams(streams, %{socket.assigns | filter_protocol: filter_protocol}),
       filter_protocol: filter_protocol
     )}
  end

  def handle_event("filter_state", %{"state" => ""}, socket) do
    streams = StreamMonitor.list_streams()

    {:noreply,
     assign(socket,
       streams: filter_streams(streams, %{socket.assigns | filter_state: nil}),
       filter_state: nil
     )}
  end

  def handle_event("filter_state", %{"state" => state}, socket) do
    streams = StreamMonitor.list_streams()
    filter_state = String.to_existing_atom(state)

    {:noreply,
     assign(socket,
       streams: filter_streams(streams, %{socket.assigns | filter_state: filter_state}),
       filter_state: filter_state
     )}
  end

  def handle_event("refresh", _params, socket) do
    streams = StreamMonitor.list_streams()
    {:noreply, assign(socket, streams: filter_streams(streams, socket.assigns))}
  end

  defp update_stream_in_list(streams, status) do
    index =
      Enum.find_index(streams, fn s ->
        s.device_id == status.device_id and s.protocol == status.protocol
      end)

    case index do
      nil -> [status | streams]
      i -> List.replace_at(streams, i, status)
    end
  end

  defp filter_streams(streams, assigns) do
    streams
    |> filter_by_protocol(assigns[:filter_protocol])
    |> filter_by_state(assigns[:filter_state])
    |> Enum.sort_by(& &1.device_hostname)
  end

  defp filter_by_protocol(streams, nil), do: streams
  defp filter_by_protocol(streams, protocol), do: Enum.filter(streams, &(&1.protocol == protocol))

  defp filter_by_state(streams, nil), do: streams
  defp filter_by_state(streams, state), do: Enum.filter(streams, &(&1.state == state))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <header class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Stream Monitor</h1>
          <p class="text-sm text-gray-500 mt-1">Real-time telemetry stream status</p>
        </div>
        <button
          phx-click="refresh"
          class="bg-gray-100 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-200"
        >
          Refresh
        </button>
      </header>

      <div class="mb-6 flex gap-4">
        <form phx-change="filter_protocol">
          <select name="protocol" class="rounded-lg border-gray-300 text-sm">
            <option value="">All Protocols</option>
            <option value="gnmi" selected={@filter_protocol == :gnmi}>gNMI</option>
            <option value="netconf" selected={@filter_protocol == :netconf}>NETCONF</option>
          </select>
        </form>
        <form phx-change="filter_state">
          <select name="state" class="rounded-lg border-gray-300 text-sm">
            <option value="">All States</option>
            <option value="connected" selected={@filter_state == :connected}>Connected</option>
            <option value="disconnected" selected={@filter_state == :disconnected}>Disconnected</option>
            <option value="reconnecting" selected={@filter_state == :reconnecting}>Reconnecting</option>
          </select>
        </form>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
        <.stat_card
          title="Total Streams"
          value={length(@streams)}
          color="gray"
        />
        <.stat_card
          title="Connected"
          value={Enum.count(@streams, &(&1.state == :connected))}
          color="green"
        />
        <.stat_card
          title="Disconnected"
          value={Enum.count(@streams, &(&1.state == :disconnected))}
          color="red"
        />
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Device</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Protocol</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">State</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Connected</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Last Message</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Messages</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Errors</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={stream <- @streams} class="hover:bg-gray-50">
              <td class="px-6 py-4">
                <.link navigate={~p"/devices/#{stream.device_id}"} class="text-indigo-600 hover:text-indigo-900 font-medium">
                  {stream.device_hostname || stream.device_id}
                </.link>
              </td>
              <td class="px-6 py-4">
                <span class={"inline-flex px-2 py-1 text-xs rounded-full #{protocol_color(stream.protocol)}"}>
                  {format_protocol(stream.protocol)}
                </span>
              </td>
              <td class="px-6 py-4">
                <span class={"inline-flex px-2 py-1 text-xs rounded-full #{state_color(stream.state)}"}>
                  {stream.state}
                </span>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {format_datetime(stream.connected_at)}
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {format_datetime(stream.last_message_at) || "-"}
              </td>
              <td class="px-6 py-4 text-sm text-gray-900 font-mono">
                {format_number(stream.message_count)}
              </td>
              <td class="px-6 py-4">
                <span :if={stream.error_count > 0} class="text-sm text-red-600 font-mono" title={stream.last_error}>
                  {stream.error_count}
                </span>
                <span :if={stream.error_count == 0} class="text-sm text-gray-400">0</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@streams == []} class="text-center py-12 text-gray-500">
        No active streams. Streams will appear when devices connect.
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow p-6">
      <dt class="text-sm font-medium text-gray-500">{@title}</dt>
      <dd class={"mt-1 text-3xl font-semibold #{stat_color(@color)}"}>
        {@value}
      </dd>
    </div>
    """
  end

  defp stat_color("green"), do: "text-green-600"
  defp stat_color("red"), do: "text-red-600"
  defp stat_color(_), do: "text-gray-900"

  defp protocol_color(:gnmi), do: "bg-blue-100 text-blue-800"
  defp protocol_color(:netconf), do: "bg-purple-100 text-purple-800"
  defp protocol_color(_), do: "bg-gray-100 text-gray-800"

  defp format_protocol(:gnmi), do: "gNMI"
  defp format_protocol(:netconf), do: "NETCONF"
  defp format_protocol(p), do: to_string(p)

  defp state_color(:connected), do: "bg-green-100 text-green-800"
  defp state_color(:disconnected), do: "bg-red-100 text-red-800"
  defp state_color(:reconnecting), do: "bg-yellow-100 text-yellow-800"
  defp state_color(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)
end

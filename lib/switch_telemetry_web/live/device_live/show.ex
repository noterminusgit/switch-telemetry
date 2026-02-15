defmodule SwitchTelemetryWeb.DeviceLive.Show do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.{Devices, Metrics}

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => id}, _session, socket) do
    device = Devices.get_device!(id)

    socket =
      socket
      |> assign(device: device, page_title: device.hostname, latest_metrics: [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "device:#{device.id}")
      send(self(), :load_metrics)
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:load_metrics, socket) do
    metrics = Metrics.get_latest(socket.assigns.device.id, limit: 50)
    {:noreply, assign(socket, latest_metrics: metrics)}
  end

  def handle_info({type, _device_id, new_metrics}, socket)
      when type in [:gnmi_metrics, :netconf_metrics] do
    existing = socket.assigns.latest_metrics

    updated =
      (new_metrics ++ existing)
      |> Enum.take(100)

    device = Devices.get_device!(socket.assigns.device.id)
    {:noreply, assign(socket, latest_metrics: updated, device: device)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.link navigate={~p"/devices"} class="text-sm text-gray-500 hover:text-gray-700">
        &larr; All Devices
      </.link>

      <header class="mt-4 mb-8">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold text-gray-900">{@device.hostname}</h1>
          <div class="flex items-center gap-3">
            <.link navigate={~p"/devices/#{@device.id}/edit"} class="text-sm text-indigo-600 hover:text-indigo-800 font-medium">
              Edit Device
            </.link>
            <.link navigate={~p"/devices/#{@device.id}/subscriptions"} class="text-sm text-indigo-600 hover:text-indigo-800 font-medium">
              Manage Subscriptions
            </.link>
          </div>
        </div>
        <div class="flex items-center gap-4 mt-2">
          <span class={"inline-flex px-2 py-1 text-xs rounded-full #{status_color(@device.status)}"}>
            {@device.status}
          </span>
          <span class="text-sm text-gray-500">{@device.ip_address}</span>
          <span class="text-sm text-gray-500">{@device.platform}</span>
          <span class="text-sm text-gray-500">Transport: {@device.transport}</span>
        </div>
      </header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div class="lg:col-span-1">
          <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-lg font-semibold mb-4">Device Details</h2>
            <dl class="space-y-3">
              <div>
                <dt class="text-xs text-gray-500">gNMI Port</dt>
                <dd class="text-sm font-medium">{@device.gnmi_port}</dd>
              </div>
              <div>
                <dt class="text-xs text-gray-500">NETCONF Port</dt>
                <dd class="text-sm font-medium">{@device.netconf_port}</dd>
              </div>
              <div>
                <dt class="text-xs text-gray-500">Collection Interval</dt>
                <dd class="text-sm font-medium">{div(@device.collection_interval_ms, 1000)}s</dd>
              </div>
              <div>
                <dt class="text-xs text-gray-500">Assigned Collector</dt>
                <dd class="text-sm font-medium">{@device.assigned_collector || "Unassigned"}</dd>
              </div>
              <div :if={@device.last_seen_at}>
                <dt class="text-xs text-gray-500">Last Seen</dt>
                <dd class="text-sm font-medium">{Calendar.strftime(@device.last_seen_at, "%Y-%m-%d %H:%M:%S UTC")}</dd>
              </div>
              <div :if={@device.tags && map_size(@device.tags) > 0}>
                <dt class="text-xs text-gray-500">Tags</dt>
                <dd class="text-sm">
                  <span
                    :for={{k, v} <- @device.tags}
                    class="inline-flex items-center px-2 py-0.5 rounded text-xs bg-gray-100 text-gray-700 mr-1 mb-1"
                  >
                    {k}: {v}
                  </span>
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <div class="lg:col-span-2">
          <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-lg font-semibold mb-4">Latest Metrics</h2>
            <div :if={@latest_metrics == []} class="text-sm text-gray-500 py-4">
              No recent metrics available.
            </div>
            <div :if={@latest_metrics != []} class="overflow-x-auto">
              <table class="min-w-full text-sm">
                <thead>
                  <tr class="border-b">
                    <th class="text-left py-2 px-2 text-xs text-gray-500">Time</th>
                    <th class="text-left py-2 px-2 text-xs text-gray-500">Path</th>
                    <th class="text-left py-2 px-2 text-xs text-gray-500">Source</th>
                    <th class="text-right py-2 px-2 text-xs text-gray-500">Value</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={metric <- @latest_metrics} class="border-b border-gray-100 hover:bg-gray-50">
                    <td class="py-1.5 px-2 text-xs text-gray-500 whitespace-nowrap">
                      {format_time(metric.time)}
                    </td>
                    <td class="py-1.5 px-2 text-xs font-mono truncate max-w-xs" title={metric.path}>
                      {metric.path}
                    </td>
                    <td class="py-1.5 px-2 text-xs text-gray-500">{metric.source}</td>
                    <td class="py-1.5 px-2 text-xs text-right font-mono">
                      {format_value(metric)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_color(:active), do: "bg-green-100 text-green-800"
  defp status_color(:inactive), do: "bg-gray-100 text-gray-800"
  defp status_color(:unreachable), do: "bg-red-100 text-red-800"
  defp status_color(:maintenance), do: "bg-yellow-100 text-yellow-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%H:%M:%S")
  end

  defp format_time(_), do: "-"

  defp format_value(metric) do
    cond do
      metric.value_float -> :erlang.float_to_binary(metric.value_float, decimals: 2)
      metric.value_int -> Integer.to_string(metric.value_int)
      metric.value_str -> metric.value_str
      true -> "-"
    end
  end
end

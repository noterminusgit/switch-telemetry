defmodule SwitchTelemetryWeb.DeviceLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Devices
  alias SwitchTelemetry.Devices.Device

  @impl true
  def mount(_params, _session, socket) do
    devices = Devices.list_devices()

    {:ok,
     assign(socket,
       devices: devices,
       page_title: "Devices",
       filter_status: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Add Device")
    |> assign(:device, %Device{id: generate_id()})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Devices")
    |> assign(:device, nil)
  end

  @impl true
  def handle_event("filter_status", %{"status" => ""}, socket) do
    {:noreply, assign(socket, devices: Devices.list_devices(), filter_status: nil)}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    devices = Devices.list_devices_by_status(status)
    {:noreply, assign(socket, devices: devices, filter_status: status)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    device = Devices.get_device!(id)
    {:ok, _} = Devices.delete_device(device)
    {:noreply, assign(socket, devices: Devices.list_devices())}
  end

  def handle_event("save", %{"device" => device_params}, socket) do
    device_params =
      device_params
      |> Map.put("id", socket.assigns.device.id)
      |> Map.put("transport", Map.get(device_params, "transport", "gnmi"))

    case Devices.create_device(device_params) do
      {:ok, _device} ->
        {:noreply,
         socket
         |> put_flash(:info, "Device added")
         |> push_navigate(to: ~p"/devices")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add device")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <header class="flex justify-between items-center mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Devices</h1>
        <.link navigate={~p"/devices/new"} class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700">
          Add Device
        </.link>
      </header>

      <div class="mb-6 flex gap-2">
        <button
          :for={status <- [nil, "active", "inactive", "unreachable", "maintenance"]}
          phx-click="filter_status"
          phx-value-status={status || ""}
          class={"px-3 py-1 rounded-full text-sm #{if @filter_status == status, do: "bg-indigo-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}"}
        >
          {status || "All"}
        </button>
      </div>

      <div :if={@live_action == :new} class="mb-8 bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Add Device</h2>
        <.simple_form for={%{}} phx-submit="save">
          <.input type="text" name="device[hostname]" label="Hostname" required />
          <.input type="text" name="device[ip_address]" label="IP Address" required />
          <.input
            type="select"
            name="device[platform]"
            label="Platform"
            options={[
              {"Cisco IOS-XR", "cisco_iosxr"},
              {"Cisco NX-OS", "cisco_nxos"},
              {"Juniper JunOS", "juniper_junos"},
              {"Arista EOS", "arista_eos"},
              {"Nokia SR OS", "nokia_sros"}
            ]}
            required
          />
          <.input
            type="select"
            name="device[transport]"
            label="Transport"
            options={[{"gNMI", "gnmi"}, {"NETCONF", "netconf"}, {"Both", "both"}]}
          />
          <:actions>
            <.button type="submit">Add Device</.button>
            <.link navigate={~p"/devices"} class="ml-4 text-gray-600">Cancel</.link>
          </:actions>
        </.simple_form>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Hostname</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">IP Address</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Platform</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Transport</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Collector</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={device <- @devices} class="hover:bg-gray-50">
              <td class="px-6 py-4">
                <.link navigate={~p"/devices/#{device.id}"} class="text-indigo-600 hover:text-indigo-900 font-medium">
                  {device.hostname}
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">{device.ip_address}</td>
              <td class="px-6 py-4 text-sm text-gray-500">{device.platform}</td>
              <td class="px-6 py-4 text-sm text-gray-500">{device.transport}</td>
              <td class="px-6 py-4">
                <span class={"inline-flex px-2 py-1 text-xs rounded-full #{status_color(device.status)}"}>
                  {device.status}
                </span>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">{device.assigned_collector || "-"}</td>
              <td class="px-6 py-4 text-right">
                <button
                  phx-click="delete"
                  phx-value-id={device.id}
                  data-confirm="Delete this device?"
                  class="text-sm text-red-600 hover:text-red-800"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@devices == []} class="text-center py-12 text-gray-500">
        No devices found.
      </div>
    </div>
    """
  end

  defp status_color(:active), do: "bg-green-100 text-green-800"
  defp status_color(:inactive), do: "bg-gray-100 text-gray-800"
  defp status_color(:unreachable), do: "bg-red-100 text-red-800"
  defp status_color(:maintenance), do: "bg-yellow-100 text-yellow-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp generate_id do
    "dev_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end
end

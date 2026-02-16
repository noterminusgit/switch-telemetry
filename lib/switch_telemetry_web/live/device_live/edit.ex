defmodule SwitchTelemetryWeb.DeviceLive.Edit do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Devices

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => id}, _session, socket) do
    device = Devices.get_device_with_credential!(id)
    changeset = Devices.change_device(device)
    credentials = Devices.list_credentials_for_select()

    {:ok,
     assign(socket,
       device: device,
       form: to_form(changeset),
       credentials: credentials,
       page_title: "Edit #{device.hostname}"
     )}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset =
      socket.assigns.device
      |> Devices.change_device(device_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"device" => device_params}, socket) do
    case Devices.update_device(socket.assigns.device, device_params) do
      {:ok, device} ->
        {:noreply,
         socket
         |> put_flash(:info, "Device updated successfully")
         |> push_navigate(to: ~p"/devices/#{device.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.link navigate={~p"/devices/#{@device.id}"} class="text-sm text-gray-500 hover:text-gray-700">
        &larr; Back to {@device.hostname}
      </.link>

      <header class="mt-4 mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Edit Device</h1>
        <p class="mt-1 text-sm text-gray-500">Update device configuration and settings.</p>
      </header>

      <div class="bg-white rounded-lg shadow p-6">
        <.simple_form for={@form} phx-change="validate" phx-submit="save">
          <div class="space-y-6">
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
              <.input
                field={@form[:hostname]}
                type="text"
                label="Hostname"
                required
              />
              <.input
                field={@form[:ip_address]}
                type="text"
                label="IP Address"
                required
              />
            </div>

            <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
              <.input
                field={@form[:platform]}
                type="select"
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
                field={@form[:transport]}
                type="select"
                label="Transport"
                options={[{"gNMI", "gnmi"}, {"NETCONF", "netconf"}, {"Both", "both"}]}
                required
              />
            </div>

            <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
              <.input
                field={@form[:gnmi_port]}
                type="number"
                label="gNMI Port"
                min="1"
                max="65535"
              />
              <.input
                field={@form[:netconf_port]}
                type="number"
                label="NETCONF Port"
                min="1"
                max="65535"
              />
            </div>

            <.input
              field={@form[:credential_id]}
              type="select"
              label="Credential"
              options={[{"None", ""} | @credentials]}
              prompt="Select a credential"
            />

            <.input
              field={@form[:collection_interval_ms]}
              type="number"
              label="Collection Interval (ms)"
              min="1000"
              step="1000"
            />

            <.input
              field={@form[:status]}
              type="select"
              label="Status"
              options={[
                {"Active", "active"},
                {"Inactive", "inactive"},
                {"Maintenance", "maintenance"}
              ]}
            />
          </div>

          <:actions>
            <.button type="submit" phx-disable-with="Saving...">
              Save Changes
            </.button>
            <.link
              navigate={~p"/devices/#{@device.id}"}
              class="ml-4 text-sm text-gray-600 hover:text-gray-900"
            >
              Cancel
            </.link>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end
end

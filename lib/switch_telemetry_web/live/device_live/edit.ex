defmodule SwitchTelemetryWeb.DeviceLive.Edit do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Devices
  alias SwitchTelemetry.Collector.ConnectionTester

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
       page_title: "Edit #{device.hostname}",
       testing_connection: false,
       connection_results: nil
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

  def handle_event("test_connection", _params, socket) do
    device = socket.assigns.device
    lv_pid = self()

    Task.start(fn ->
      results =
        try do
          ConnectionTester.test_connection(device)
        rescue
          e ->
            [
              %{
                protocol: :unknown,
                success: false,
                message: "Error: #{Exception.message(e)}",
                elapsed_ms: 0
              }
            ]
        end

      send(lv_pid, {:connection_test_result, results})
    end)

    Process.send_after(self(), :connection_test_timeout, 45_000)

    {:noreply, assign(socket, testing_connection: true, connection_results: nil)}
  end

  @impl true
  def handle_info({:connection_test_result, results}, socket) do
    {:noreply, assign(socket, testing_connection: false, connection_results: results)}
  end

  def handle_info(:connection_test_timeout, socket) do
    if socket.assigns.testing_connection do
      {:noreply, assign(socket, testing_connection: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

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
                  {"Cisco IOS-XE", "cisco_iosxe"},
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
            />

            <.input
              field={@form[:secure_mode]}
              type="checkbox"
              label="Secure Mode (require credentials for gNMI)"
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

        <div class="mt-6 border-t pt-6">
          <h3 class="text-sm font-medium text-gray-900 mb-3">Connection Test</h3>
          <button
            phx-click="test_connection"
            disabled={@testing_connection}
            class={"inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md #{if @testing_connection, do: "text-gray-400 bg-gray-100 cursor-not-allowed", else: "text-gray-700 bg-white hover:bg-gray-50"}"}
          >
            <%= if @testing_connection do %>
              <svg
                class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
              Testing...
            <% else %>
              Test Connection
            <% end %>
          </button>

          <%= if @connection_results do %>
            <div class="mt-4 space-y-2">
              <%= for result <- @connection_results do %>
                <div class={"flex items-center p-3 rounded-md text-sm #{if result.success, do: "bg-green-50 text-green-800", else: "bg-red-50 text-red-800"}"}>
                  <%= if result.success do %>
                    <svg class="h-5 w-5 text-green-400 mr-2" viewBox="0 0 20 20" fill="currentColor">
                      <path
                        fill-rule="evenodd"
                        d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  <% else %>
                    <svg class="h-5 w-5 text-red-400 mr-2" viewBox="0 0 20 20" fill="currentColor">
                      <path
                        fill-rule="evenodd"
                        d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  <% end %>
                  <span class="font-medium uppercase mr-2"><%= result.protocol %></span>
                  <span><%= result.message %></span>
                  <span class="ml-auto text-xs text-gray-500"><%= result.elapsed_ms %>ms</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

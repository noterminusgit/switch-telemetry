defmodule SwitchTelemetryWeb.CredentialLive.Show do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Devices

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    credential = Devices.get_credential!(id)

    {:ok,
     assign(socket,
       credential: credential,
       page_title: credential.name
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.link navigate={~p"/credentials"} class="text-sm text-gray-500 hover:text-gray-700">
        &larr; All Credentials
      </.link>

      <header class="mt-4 mb-8 flex justify-between items-start">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">{@credential.name}</h1>
          <p class="mt-1 text-sm text-gray-500">Credential details and configuration.</p>
        </div>
        <.link
          navigate={~p"/credentials/#{@credential.id}/edit"}
          class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 text-sm"
        >
          Edit
        </.link>
      </header>

      <div class="bg-white rounded-lg shadow p-6">
        <dl class="grid grid-cols-1 gap-6 sm:grid-cols-2">
          <div>
            <dt class="text-sm font-medium text-gray-500">Name</dt>
            <dd class="mt-1 text-sm text-gray-900">{@credential.name}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Username</dt>
            <dd class="mt-1 text-sm text-gray-900">{@credential.username}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Password</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {if @credential.password, do: "********", else: "Not set"}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">SSH Key</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {if @credential.ssh_key, do: "Configured", else: "Not set"}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">TLS Certificate</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {if @credential.tls_cert, do: "Configured", else: "Not set"}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">TLS Key</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {if @credential.tls_key, do: "Configured", else: "Not set"}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Created</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {Calendar.strftime(@credential.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Updated</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {Calendar.strftime(@credential.updated_at, "%Y-%m-%d %H:%M:%S UTC")}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end
end

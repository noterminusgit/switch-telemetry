defmodule SwitchTelemetryWeb.CredentialLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Devices
  alias SwitchTelemetry.Devices.Credential

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    credentials = Devices.list_credentials()

    {:ok,
     assign(socket,
       credentials: credentials,
       page_title: "Credentials"
     )}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Credentials")
    |> assign(:credential, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Credential")
    |> assign(:credential, %Credential{id: generate_id()})
    |> assign(:changeset, to_form(Devices.change_credential(%Credential{id: generate_id()})))
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("delete", %{"id" => id}, socket) do
    credential = Devices.get_credential!(id)

    case Devices.delete_credential(credential) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(credentials: Devices.list_credentials())
         |> put_flash(:info, "Credential deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete credential")}
    end
  end

  def handle_event("validate", %{"credential" => credential_params}, socket) do
    changeset =
      %Credential{id: socket.assigns.credential.id}
      |> Devices.change_credential(credential_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: to_form(changeset))}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    credential_params = Map.put(credential_params, "id", socket.assigns.credential.id)

    case Devices.create_credential(credential_params) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential created")
         |> push_navigate(to: ~p"/credentials")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: to_form(changeset))}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <header class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Credentials</h1>
          <p class="mt-1 text-sm text-gray-500">Manage device authentication credentials.</p>
        </div>
        <.link
          navigate={~p"/credentials/new"}
          class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700"
        >
          New Credential
        </.link>
      </header>

      <div :if={@live_action == :new} class="mb-8 bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Create Credential</h2>
        <.simple_form for={@changeset} phx-change="validate" phx-submit="save">
          <.input field={@changeset[:name]} type="text" label="Name" required />
          <.input field={@changeset[:username]} type="text" label="Username" required />
          <.input field={@changeset[:password]} type="password" label="Password" />
          <.input field={@changeset[:ssh_key]} type="textarea" label="SSH Private Key" rows="4" />
          <.input field={@changeset[:tls_cert]} type="textarea" label="TLS Certificate" rows="4" />
          <.input field={@changeset[:tls_key]} type="textarea" label="TLS Private Key" rows="4" />
          <:actions>
            <.button type="submit" phx-disable-with="Creating...">Create Credential</.button>
            <.link navigate={~p"/credentials"} class="ml-4 text-gray-600">Cancel</.link>
          </:actions>
        </.simple_form>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Username</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Auth Type</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={credential <- @credentials} class="hover:bg-gray-50">
              <td class="px-6 py-4">
                <.link
                  navigate={~p"/credentials/#{credential.id}"}
                  class="text-indigo-600 hover:text-indigo-900 font-medium"
                >
                  {credential.name}
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">{credential.username}</td>
              <td class="px-6 py-4 text-sm text-gray-500">{auth_type(credential)}</td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {Calendar.strftime(credential.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="px-6 py-4 text-right space-x-2">
                <.link
                  navigate={~p"/credentials/#{credential.id}/edit"}
                  class="text-sm text-indigo-600 hover:text-indigo-800"
                >
                  Edit
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={credential.id}
                  data-confirm="Delete this credential? Devices using it will lose access."
                  class="text-sm text-red-600 hover:text-red-800"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@credentials == []} class="text-center py-12 text-gray-500">
          No credentials configured. Create one to authenticate with devices.
        </div>
      </div>
    </div>
    """
  end

  defp auth_type(credential) do
    cond do
      credential.tls_cert && credential.tls_key -> "TLS"
      credential.ssh_key -> "SSH Key"
      credential.password -> "Password"
      true -> "None"
    end
  end

  defp generate_id do
    "cred_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end
end

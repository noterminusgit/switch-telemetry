defmodule SwitchTelemetryWeb.CredentialLive.Edit do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Devices

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => id}, _session, socket) do
    credential = Devices.get_credential!(id)
    changeset = Devices.change_credential(credential)

    {:ok,
     assign(socket,
       credential: credential,
       changeset: to_form(changeset),
       page_title: "Edit #{credential.name}"
     )}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"credential" => credential_params}, socket) do
    changeset =
      socket.assigns.credential
      |> Devices.change_credential(credential_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: to_form(changeset))}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    case Devices.update_credential(socket.assigns.credential, credential_params) do
      {:ok, credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential updated successfully")
         |> push_navigate(to: ~p"/credentials/#{credential.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: to_form(changeset))}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.link navigate={~p"/credentials/#{@credential.id}"} class="text-sm text-gray-500 hover:text-gray-700">
        &larr; Back to {@credential.name}
      </.link>

      <header class="mt-4 mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Edit Credential</h1>
        <p class="mt-1 text-sm text-gray-500">Update credential settings. Leave password fields blank to keep existing values.</p>
      </header>

      <div class="bg-white rounded-lg shadow p-6">
        <.simple_form for={@changeset} phx-change="validate" phx-submit="save">
          <div class="space-y-6">
            <.input field={@changeset[:name]} type="text" label="Name" required />
            <.input field={@changeset[:username]} type="text" label="Username" required />

            <div class="border-t border-gray-200 pt-6">
              <h3 class="text-sm font-medium text-gray-900 mb-4">Authentication</h3>
              <p class="text-sm text-gray-500 mb-4">
                Leave fields blank to keep existing values. Clear a field and save to remove it.
              </p>

              <div class="space-y-6">
                <.input
                  field={@changeset[:password]}
                  type="password"
                  label="Password"
                  placeholder="Enter new password or leave blank"
                />

                <.input
                  field={@changeset[:ssh_key]}
                  type="textarea"
                  label="SSH Private Key"
                  rows="4"
                  placeholder="Paste SSH private key here"
                />

                <.input
                  field={@changeset[:tls_cert]}
                  type="textarea"
                  label="TLS Certificate"
                  rows="4"
                  placeholder="Paste TLS certificate (PEM format)"
                />

                <.input
                  field={@changeset[:tls_key]}
                  type="textarea"
                  label="TLS Private Key"
                  rows="4"
                  placeholder="Paste TLS private key (PEM format)"
                />
              </div>
            </div>
          </div>

          <:actions>
            <.button type="submit" phx-disable-with="Saving...">
              Save Changes
            </.button>
            <.link
              navigate={~p"/credentials/#{@credential.id}"}
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

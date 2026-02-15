defmodule SwitchTelemetryWeb.AdminEmailLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetry.Accounts.AdminEmail

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin Email Allowlist")
     |> assign(:admin_emails, Accounts.list_admin_emails())}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    socket
    |> assign(:page_title, "Add Admin Email")
    |> assign(:admin_email, %AdminEmail{})
    |> assign(:form, to_form(Accounts.change_admin_email(%AdminEmail{})))
  end

  defp apply_action(socket, :index) do
    socket
    |> assign(:page_title, "Admin Email Allowlist")
    |> assign(:admin_email, nil)
    |> assign(:form, nil)
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        Admin Email Allowlist
        <:subtitle>Manage which emails get automatic admin access</:subtitle>
        <:actions>
          <.link patch={~p"/admin/admin_emails/new"}>
            <.button>Add Email</.button>
          </.link>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="mt-6 bg-white rounded-lg shadow p-6">
        <.header>
          Add Admin Email
        </.header>
        <.simple_form
          for={@form}
          id="admin-email-form"
          phx-change="validate"
          phx-submit="save"
        >
          <.input field={@form[:email]} type="email" label="Email" />
          <:actions>
            <.link patch={~p"/admin/admin_emails"} class="text-sm text-gray-600 hover:text-gray-800">
              Cancel
            </.link>
            <.button phx-disable-with="Saving...">Save</.button>
          </:actions>
        </.simple_form>
      </div>

      <div class="mt-8 bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Added</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={admin_email <- @admin_emails} class="hover:bg-gray-50">
              <td class="px-6 py-4 text-sm font-medium text-gray-900">{admin_email.email}</td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {Calendar.strftime(admin_email.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="px-6 py-4 text-right">
                <button
                  phx-click="delete"
                  phx-value-id={admin_email.id}
                  data-confirm="Remove this email from the admin allowlist?"
                  class="text-sm text-red-600 hover:text-red-800"
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@admin_emails == []} class="text-center py-12 text-gray-500">
        No emails on the allowlist yet.
      </div>
    </div>
    """
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"admin_email" => params}, socket) do
    changeset =
      %AdminEmail{}
      |> Accounts.change_admin_email(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"admin_email" => params}, socket) do
    case Accounts.create_admin_email(params) do
      {:ok, _admin_email} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin email added.")
         |> assign(:admin_emails, Accounts.list_admin_emails())
         |> push_patch(to: ~p"/admin/admin_emails")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    admin_email = Accounts.get_admin_email!(id)

    case Accounts.delete_admin_email(admin_email) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin email removed.")
         |> assign(:admin_emails, Accounts.list_admin_emails())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove admin email.")}
    end
  end
end

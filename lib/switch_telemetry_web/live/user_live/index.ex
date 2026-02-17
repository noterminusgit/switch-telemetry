defmodule SwitchTelemetryWeb.UserLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetry.Accounts.{AdminEmail, User}

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:users, Accounts.list_users())
     |> assign(:admin_emails, Accounts.list_admin_emails())
     |> assign(:admin_email_form, to_form(Accounts.change_admin_email(%AdminEmail{})))}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    socket
    |> assign(:page_title, "Add User")
    |> assign(:user_form, to_form(Accounts.change_user_registration(%User{})))
  end

  defp apply_action(socket, :index) do
    socket
    |> assign(:page_title, "User Management")
    |> assign(:user_form, nil)
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        User Management
        <:subtitle>Manage user accounts and roles</:subtitle>
        <:actions>
          <.link patch={~p"/admin/users/new"}>
            <.button>Add User</.button>
          </.link>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="mt-6 bg-white rounded-lg shadow p-6">
        <.header>
          Add User
        </.header>
        <.simple_form
          for={@user_form}
          id="new-user-form"
          phx-change="validate_user"
          phx-submit="save_user"
        >
          <.input field={@user_form[:email]} type="email" label="Email" />
          <.input field={@user_form[:password]} type="password" label="Password" />
          <.input
            field={@user_form[:role]}
            type="select"
            label="Role"
            options={[{"Admin", "admin"}, {"Operator", "operator"}, {"Viewer", "viewer"}]}
          />
          <:actions>
            <.link patch={~p"/admin/users"} class="text-sm text-gray-600 hover:text-gray-800">
              Cancel
            </.link>
            <.button phx-disable-with="Creating...">Create User</.button>
          </:actions>
        </.simple_form>
      </div>

      <div class="mt-8 bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Role</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Confirmed
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Created
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={user <- @users} class="hover:bg-gray-50">
              <td class="px-6 py-4 text-sm font-medium text-gray-900">{user.email}</td>
              <td class="px-6 py-4">
                <form phx-change="change_role" phx-value-user-id={user.id}>
                  <select
                    name="role"
                    class="text-sm border-gray-300 rounded-md"
                    disabled={user.id == @current_user.id}
                  >
                    <option value="admin" selected={user.role == :admin}>Admin</option>
                    <option value="operator" selected={user.role == :operator}>Operator</option>
                    <option value="viewer" selected={user.role == :viewer}>Viewer</option>
                  </select>
                </form>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {if user.confirmed_at, do: "Yes", else: "No"}
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="px-6 py-4 text-right">
                <button
                  :if={user.id != @current_user.id}
                  phx-click="delete_user"
                  phx-value-id={user.id}
                  data-confirm="Are you sure you want to delete this user?"
                  class="text-sm text-red-600 hover:text-red-800"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@users == []} class="text-center py-12 text-gray-500">
        No users found.
      </div>

      <%!-- Admin Email Allowlist Section --%>
      <div class="mt-12">
        <.header>
          Admin Email Allowlist
          <:subtitle>Emails on this list get automatic admin access on registration</:subtitle>
        </.header>

        <div class="mt-6 bg-white rounded-lg shadow p-6">
          <.simple_form
            for={@admin_email_form}
            id="admin-email-form"
            phx-change="validate_admin_email"
            phx-submit="save_admin_email"
          >
            <.input field={@admin_email_form[:email]} type="email" label="Add email to allowlist" />
            <:actions>
              <.button phx-disable-with="Adding...">Add Email</.button>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@admin_emails != []} class="mt-4 bg-white rounded-lg shadow overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Email
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Added
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                  Actions
                </th>
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
                    phx-click="delete_admin_email"
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

        <div :if={@admin_emails == []} class="text-center py-8 text-gray-500">
          No emails on the allowlist yet.
        </div>
      </div>
    </div>
    """
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}

  # User creation events
  def handle_event("validate_user", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :user_form, to_form(changeset))}
  end

  def handle_event("save_user", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created successfully.")
         |> assign(:users, Accounts.list_users())
         |> push_patch(to: ~p"/admin/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_form, to_form(changeset))}
    end
  end

  # Role management
  def handle_event("change_role", %{"role" => role, "user-id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    case Accounts.update_user_role(user, %{role: String.to_existing_atom(role)}) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role updated.")
         |> assign(:users, Accounts.list_users())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update role.")}
    end
  end

  # User deletion
  def handle_event("delete_user", %{"id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    case Accounts.delete_user(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User deleted.")
         |> assign(:users, Accounts.list_users())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user.")}
    end
  end

  # Admin email allowlist events
  def handle_event("validate_admin_email", %{"admin_email" => params}, socket) do
    changeset =
      %AdminEmail{}
      |> Accounts.change_admin_email(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :admin_email_form, to_form(changeset))}
  end

  def handle_event("save_admin_email", %{"admin_email" => params}, socket) do
    case Accounts.create_admin_email(params) do
      {:ok, _admin_email} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin email added.")
         |> assign(:admin_emails, Accounts.list_admin_emails())
         |> assign(:admin_email_form, to_form(Accounts.change_admin_email(%AdminEmail{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :admin_email_form, to_form(changeset))}
    end
  end

  def handle_event("delete_admin_email", %{"id" => id}, socket) do
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

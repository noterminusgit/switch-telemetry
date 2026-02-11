defmodule SwitchTelemetryWeb.UserLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User Management")
     |> assign(:users, Accounts.list_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        User Management
        <:subtitle>Manage user accounts and roles</:subtitle>
      </.header>

      <div class="mt-8 bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Role</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Confirmed</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
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
    </div>
    """
  end

  @impl true
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
end

defmodule SwitchTelemetryWeb.DashboardLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetry.Dashboards.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    dashboards = Dashboards.list_dashboards()
    {:ok, assign(socket, dashboards: dashboards, page_title: "Dashboards")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Dashboard")
    |> assign(:dashboard, %Dashboard{id: generate_id()})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dashboards")
    |> assign(:dashboard, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    dashboard = Dashboards.get_dashboard!(id)
    {:ok, _} = Dashboards.delete_dashboard(dashboard)
    {:noreply, assign(socket, dashboards: Dashboards.list_dashboards())}
  end

  def handle_event("clone", %{"id" => id}, socket) do
    dashboard = Dashboards.get_dashboard!(id)
    current_user_id = socket.assigns.current_user && socket.assigns.current_user.id

    case Dashboards.clone_dashboard(dashboard, current_user_id) do
      {:ok, _clone} ->
        {:noreply,
         socket
         |> put_flash(:info, "Dashboard cloned")
         |> assign(dashboards: Dashboards.list_dashboards())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clone dashboard")}
    end
  end

  def handle_event("save", %{"dashboard" => dashboard_params}, socket) do
    dashboard_params = Map.put(dashboard_params, "id", socket.assigns.dashboard.id)

    case Dashboards.create_dashboard(dashboard_params) do
      {:ok, _dashboard} ->
        {:noreply,
         socket
         |> put_flash(:info, "Dashboard created")
         |> push_navigate(to: ~p"/dashboards")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <header class="flex justify-between items-center mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Dashboards</h1>
        <.link navigate={~p"/dashboards/new"} class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700">
          New Dashboard
        </.link>
      </header>

      <div :if={@live_action == :new} class="mb-8 bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Create Dashboard</h2>
        <.simple_form for={%{}} phx-submit="save">
          <.input type="text" name="dashboard[name]" label="Name" required />
          <.input type="textarea" name="dashboard[description]" label="Description" />
          <:actions>
            <.button type="submit">Create</.button>
            <.link navigate={~p"/dashboards"} class="ml-4 text-gray-600">Cancel</.link>
          </:actions>
        </.simple_form>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div :for={dashboard <- @dashboards} class="bg-white rounded-lg shadow hover:shadow-md transition-shadow p-6">
          <.link navigate={~p"/dashboards/#{dashboard.id}"} class="block">
            <h2 class="text-lg font-semibold text-gray-900">{dashboard.name}</h2>
            <p :if={dashboard.description} class="text-sm text-gray-500 mt-1">{dashboard.description}</p>
            <div class="flex items-center gap-4 mt-4 text-xs text-gray-400">
              <span>Layout: {dashboard.layout}</span>
              <span>Refresh: {div(dashboard.refresh_interval_ms, 1000)}s</span>
            </div>
          </.link>
          <div class="mt-4 flex justify-end gap-3">
            <button
              phx-click="clone"
              phx-value-id={dashboard.id}
              class="text-sm text-indigo-600 hover:text-indigo-800"
            >
              Clone
            </button>
            <button
              phx-click="delete"
              phx-value-id={dashboard.id}
              data-confirm="Delete this dashboard?"
              class="text-sm text-red-600 hover:text-red-800"
            >
              Delete
            </button>
          </div>
        </div>
      </div>

      <div :if={@dashboards == []} class="text-center py-12 text-gray-500">
        No dashboards yet. Create one to get started.
      </div>
    </div>
    """
  end

  defp generate_id do
    "dash_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end
end

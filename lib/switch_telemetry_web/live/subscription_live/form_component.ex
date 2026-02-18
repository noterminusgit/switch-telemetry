defmodule SwitchTelemetryWeb.SubscriptionLive.FormComponent do
  use SwitchTelemetryWeb, :live_component

  alias SwitchTelemetry.Collector
  alias SwitchTelemetry.Collector.{GnmiCapabilities, SubscriptionPaths}
  alias SwitchTelemetry.Devices

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{enumerate_result: {:ok, result}} = _assigns, socket) do
    device = Devices.get_device!(socket.assigns.device.id)
    available_paths = SubscriptionPaths.list_paths(device.platform, device.model)
    categories = available_paths |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()

    {:ok,
     socket
     |> assign(
       device: device,
       available_paths: available_paths,
       categories: categories,
       enumerating: false,
       enumerate_error: nil
     )
     |> maybe_add_discovered_paths(result.paths)}
  end

  def update(%{enumerate_result: {:error, reason}} = _assigns, socket) do
    {:ok,
     assign(socket,
       enumerating: false,
       enumerate_error: "Failed to enumerate paths: #{inspect(reason)}"
     )}
  end

  def update(assigns, socket) do
    device = assigns.device
    available_paths = SubscriptionPaths.list_paths(device.platform, device.model)
    categories = available_paths |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()

    selected_paths =
      assigns.subscription.paths
      |> List.wrap()
      |> MapSet.new()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       available_paths: available_paths,
       categories: categories,
       selected_paths: selected_paths,
       path_filter: "",
       enumerating: false,
       enumerate_error: nil
     )
     |> assign_form_values()}
  end

  defp maybe_add_discovered_paths(socket, discovered_paths) do
    known = MapSet.new(Enum.map(socket.assigns.available_paths, & &1.path))

    new_paths =
      discovered_paths
      |> Enum.reject(&MapSet.member?(known, &1))

    selected = Enum.reduce(new_paths, socket.assigns.selected_paths, &MapSet.put(&2, &1))
    assign(socket, selected_paths: selected)
  end

  defp assign_form_values(socket) do
    subscription = socket.assigns.subscription

    sample_interval_ns = subscription.sample_interval_ns || 30_000_000_000
    sample_interval_seconds = div(sample_interval_ns, 1_000_000_000)

    assign(socket,
      form_values: %{
        "mode" => (subscription.mode && to_string(subscription.mode)) || "stream",
        "sample_interval_seconds" => to_string(sample_interval_seconds),
        "encoding" => (subscription.encoding && to_string(subscription.encoding)) || "proto",
        "enabled" => subscription.enabled != false
      }
    )
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("save", %{"subscription" => subscription_params}, socket) do
    subscription_params = prepare_params(subscription_params, socket)

    result =
      case socket.assigns.action do
        :new ->
          Collector.create_subscription(subscription_params)

        :edit ->
          Collector.update_subscription(socket.assigns.subscription, subscription_params)
      end

    case result do
      {:ok, _subscription} ->
        device_id = socket.assigns.device.id

        {:noreply,
         socket
         |> put_flash(:info, "Subscription saved")
         |> push_navigate(to: ~p"/devices/#{device_id}/subscriptions")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, format_errors(changeset))
         |> assign_form_values()}
    end
  end

  def handle_event("toggle_path", %{"path" => path}, socket) do
    selected = socket.assigns.selected_paths

    selected =
      if MapSet.member?(selected, path) do
        MapSet.delete(selected, path)
      else
        MapSet.put(selected, path)
      end

    {:noreply, assign(socket, selected_paths: selected)}
  end

  def handle_event("filter_paths", %{"path_filter" => filter}, socket) do
    {:noreply, assign(socket, path_filter: filter)}
  end

  def handle_event("select_all_visible", _params, socket) do
    visible = filtered_paths(socket.assigns.available_paths, socket.assigns.path_filter)
    selected = Enum.reduce(visible, socket.assigns.selected_paths, &MapSet.put(&2, &1.path))
    {:noreply, assign(socket, selected_paths: selected)}
  end

  def handle_event("deselect_all_visible", _params, socket) do
    visible = filtered_paths(socket.assigns.available_paths, socket.assigns.path_filter)
    visible_set = MapSet.new(visible, & &1.path)
    selected = MapSet.difference(socket.assigns.selected_paths, visible_set)
    {:noreply, assign(socket, selected_paths: selected)}
  end

  def handle_event("enumerate_from_device", _params, socket) do
    device = socket.assigns.device
    component_id = socket.assigns.id
    parent_pid = self()

    Task.start(fn ->
      result = GnmiCapabilities.enumerate_and_save(device)
      send(parent_pid, {:enumerate_result, component_id, result})
    end)

    {:noreply, assign(socket, enumerating: true, enumerate_error: nil)}
  end

  defp prepare_params(params, socket) do
    paths = socket.assigns.selected_paths |> MapSet.to_list()

    enabled = Map.get(params, "enabled", "false") == "true"

    sample_interval_ns =
      case Integer.parse(Map.get(params, "sample_interval_seconds", "30")) do
        {seconds, _} when seconds > 0 -> seconds * 1_000_000_000
        _ -> 30_000_000_000
      end

    params
    |> Map.put("paths", paths)
    |> Map.put("enabled", enabled)
    |> Map.put("sample_interval_ns", sample_interval_ns)
    |> Map.put("id", socket.assigns.subscription.id)
    |> Map.put("device_id", socket.assigns.device.id)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp filtered_paths(available_paths, "") do
    available_paths
  end

  defp filtered_paths(available_paths, filter) do
    filter_down = String.downcase(filter)

    Enum.filter(available_paths, fn entry ->
      String.contains?(String.downcase(entry.path), filter_down) or
        String.contains?(String.downcase(entry.description), filter_down)
    end)
  end

  defp filtered_paths_for_category(available_paths, filter, category) do
    available_paths
    |> filtered_paths(filter)
    |> Enum.filter(&(&1.category == category))
  end

  defp orphaned_paths(selected_paths, available_paths) do
    known = MapSet.new(Enum.map(available_paths, & &1.path))

    selected_paths
    |> MapSet.to_list()
    |> Enum.filter(&(not MapSet.member?(known, &1)))
    |> Enum.sort()
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assigns
      |> assign(:orphaned, orphaned_paths(assigns.selected_paths, assigns.available_paths))
      |> assign(
        :visible_count,
        length(filtered_paths(assigns.available_paths, assigns.path_filter))
      )

    ~H"""
    <div>
      <.simple_form for={%{}} phx-submit="save" phx-target={@myself}>
        <div class="mb-4">
          <div class="flex items-center justify-between mb-2">
            <label class="block text-sm font-semibold text-gray-700">
              Subscription Paths
              <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                {MapSet.size(@selected_paths)} selected
              </span>
            </label>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="select_all_visible"
                phx-target={@myself}
                class="text-xs text-indigo-600 hover:text-indigo-800"
              >
                Select all
              </button>
              <button
                type="button"
                phx-click="deselect_all_visible"
                phx-target={@myself}
                class="text-xs text-gray-500 hover:text-gray-700"
              >
                Deselect all
              </button>
              <button
                type="button"
                phx-click="enumerate_from_device"
                phx-target={@myself}
                disabled={@enumerating}
                class="text-xs text-emerald-600 hover:text-emerald-800 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <span :if={@enumerating} class="inline-flex items-center gap-1">
                  <svg class="animate-spin h-3 w-3" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none" />
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  Enumerating...
                </span>
                <span :if={!@enumerating}>Enumerate from device</span>
              </button>
            </div>
          </div>

          <div :if={@enumerate_error} class="mb-2 text-sm text-red-600 bg-red-50 rounded px-3 py-2">
            {@enumerate_error}
          </div>

          <input
            type="text"
            name="path_filter"
            value={@path_filter}
            placeholder="Filter paths..."
            phx-change="filter_paths"
            phx-debounce="200"
            phx-target={@myself}
            class="w-full mb-3 rounded-md border-gray-300 shadow-sm text-sm focus:border-indigo-500 focus:ring-indigo-500"
          />

          <div class="border rounded-lg bg-gray-50 max-h-80 overflow-y-auto">
            <div :for={category <- @categories} class="mb-1">
              <% cat_paths = filtered_paths_for_category(@available_paths, @path_filter, category) %>
              <div :if={cat_paths != []} >
                <div class="sticky top-0 bg-gray-100 px-4 py-1.5 border-b">
                  <h4 class="text-xs font-semibold text-gray-500 uppercase">{category}</h4>
                </div>
                <div :for={entry <- cat_paths} class="flex items-center px-4 py-1.5 hover:bg-gray-100">
                  <label class="flex items-center gap-2 cursor-pointer w-full">
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@selected_paths, entry.path)}
                      phx-click="toggle_path"
                      phx-value-path={entry.path}
                      phx-target={@myself}
                      class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                    />
                    <code class="text-xs text-gray-700">{entry.path}</code>
                    <span class="text-xs text-gray-400 ml-auto">{entry.description}</span>
                  </label>
                </div>
              </div>
            </div>

            <div :if={@orphaned != []} class="mb-1">
              <div class="sticky top-0 bg-gray-100 px-4 py-1.5 border-b">
                <h4 class="text-xs font-semibold text-gray-500 uppercase">custom</h4>
              </div>
              <div :for={path <- @orphaned} class="flex items-center px-4 py-1.5 hover:bg-gray-100">
                <label class="flex items-center gap-2 cursor-pointer w-full">
                  <input
                    type="checkbox"
                    checked
                    phx-click="toggle_path"
                    phx-value-path={path}
                    phx-target={@myself}
                    class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                  />
                  <code class="text-xs text-gray-700">{path}</code>
                  <span class="text-xs text-gray-400 ml-auto">Custom path</span>
                </label>
              </div>
            </div>

            <div :if={@visible_count == 0 && @orphaned == []} class="px-4 py-6 text-center text-sm text-gray-400">
              No paths match your filter.
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            type="select"
            name="subscription[mode]"
            label="Mode"
            options={[
              {"Stream (continuous updates)", "stream"},
              {"Poll (periodic requests)", "poll"},
              {"Once (single request)", "once"}
            ]}
            value={@form_values["mode"]}
          />
          <.input
            type="select"
            name="subscription[encoding]"
            label="Encoding"
            options={[
              {"Proto (binary)", "proto"},
              {"JSON", "json"},
              {"JSON IETF", "json_ietf"}
            ]}
            value={@form_values["encoding"]}
          />
        </div>
        <.input
          type="number"
          name="subscription[sample_interval_seconds]"
          label="Sample Interval (seconds)"
          value={@form_values["sample_interval_seconds"]}
          min="1"
          step="1"
        />
        <.input
          type="checkbox"
          name="subscription[enabled]"
          label="Enabled"
          value={@form_values["enabled"]}
        />
        <:actions>
          <.button type="submit">
            {if @action == :new, do: "Create Subscription", else: "Update Subscription"}
          </.button>
          <.link navigate={~p"/devices/#{@device.id}/subscriptions"} class="ml-4 text-gray-600">
            Cancel
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end

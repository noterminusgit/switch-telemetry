defmodule SwitchTelemetryWeb.Components.WidgetEditor do
  @moduledoc """
  LiveComponent providing a form for creating and editing dashboard widgets.

  Manages the widget form fields (title, chart_type, time_range) through a
  standard Phoenix form changeset, and handles the queries list (dynamic
  series builder) via component assigns with phx-click events.
  """
  use SwitchTelemetryWeb, :live_component
  require Logger

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetry.Dashboards.Widget

  @impl true
  def update(assigns, socket) do
    widget = assigns[:widget]
    action = assigns[:action]

    queries =
      if widget && widget.queries && widget.queries != [] do
        widget.queries
      else
        [empty_query()]
      end

    changeset =
      if widget do
        Dashboards.change_widget(widget)
      else
        Dashboards.change_widget(%Widget{})
      end

    time_range_value =
      if widget do
        get_time_range_duration(widget.time_range)
      else
        "1h"
      end

    device_options = Dashboards.list_devices_for_widget_picker()

    path_options_map =
      queries
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {query, index}, acc ->
        device_id = query["device_id"]

        if device_id && device_id != "" do
          Map.put(acc, index, Dashboards.list_paths_for_device(device_id))
        else
          acc
        end
      end)

    socket =
      socket
      |> assign(assigns)
      |> assign(
        form: to_form(changeset),
        queries: queries,
        time_range_value: time_range_value,
        action: action,
        device_options: device_options,
        path_options_map: path_options_map
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"widget" => params}, socket) do
    widget = socket.assigns[:widget] || %Widget{}

    changeset =
      widget
      |> Widget.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"widget" => params}, socket) do
    dashboard = socket.assigns.dashboard
    queries = socket.assigns.queries
    time_range_value = params["time_range"] || socket.assigns.time_range_value

    time_range = %{"type" => "relative", "duration" => time_range_value}

    attrs =
      params
      |> Map.put("queries", queries)
      |> Map.put("time_range", time_range)

    case socket.assigns.action do
      :add_widget ->
        id = generate_widget_id()

        attrs = Map.put(attrs, "id", id)

        case Dashboards.add_widget(dashboard, attrs) do
          {:ok, _widget} ->
            dashboard = Dashboards.get_dashboard!(dashboard.id)
            send(self(), {:widget_saved, dashboard})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      :edit_widget ->
        case Dashboards.update_widget(socket.assigns.widget, attrs) do
          {:ok, _widget} ->
            dashboard = Dashboards.get_dashboard!(dashboard.id)
            send(self(), {:widget_saved, dashboard})
            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
    end
  end

  def handle_event("add_query", _params, socket) do
    queries = socket.assigns.queries ++ [empty_query()]
    {:noreply, assign(socket, queries: queries)}
  end

  def handle_event("remove_query", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    queries = List.delete_at(socket.assigns.queries, index)
    queries = if queries == [], do: [empty_query()], else: queries

    # Re-index path_options_map after removal
    old_map = socket.assigns.path_options_map

    path_options_map =
      queries
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {_query, new_idx}, acc ->
        # After removing index, items at old positions shift down
        old_idx = if new_idx >= index, do: new_idx + 1, else: new_idx

        case Map.get(old_map, old_idx) do
          nil -> acc
          paths -> Map.put(acc, new_idx, paths)
        end
      end)

    {:noreply, assign(socket, queries: queries, path_options_map: path_options_map)}
  end

  def handle_event("select_device", %{"select_device" => _} = params, socket) do
    {index, device_id} = extract_indexed_param(params, "select_device")

    Logger.debug("WidgetEditor select_device: index=#{index}, device_id=#{inspect(device_id)}")

    queries =
      List.update_at(socket.assigns.queries, index, fn query ->
        query
        |> Map.put("device_id", device_id)
        |> Map.put("path", "")
      end)

    path_options_map =
      if device_id != "" do
        paths = Dashboards.list_paths_for_device(device_id)

        Logger.debug(
          "WidgetEditor select_device: path_count=#{length(paths)}, " <>
            "categories=#{inspect(Enum.map(paths, &elem(&1, 0)))}"
        )

        Map.put(socket.assigns.path_options_map, index, paths)
      else
        Map.delete(socket.assigns.path_options_map, index)
      end

    {:noreply, assign(socket, queries: queries, path_options_map: path_options_map)}
  end

  def handle_event("select_path", %{"select_path" => _} = params, socket) do
    {index, path} = extract_indexed_param(params, "select_path")

    queries =
      List.update_at(socket.assigns.queries, index, fn query ->
        Map.put(query, "path", path)
      end)

    {:noreply, assign(socket, queries: queries)}
  end

  def handle_event("update_color", %{"update_color" => _} = params, socket) do
    {index, color} = extract_indexed_param(params, "update_color")

    queries =
      List.update_at(socket.assigns.queries, index, fn query ->
        Map.put(query, "color", color)
      end)

    {:noreply, assign(socket, queries: queries)}
  end

  def handle_event("update_query", %{"index" => index_str} = params, socket) do
    index = String.to_integer(index_str)
    field = params["field"]
    value = params["value"]

    queries =
      List.update_at(socket.assigns.queries, index, fn query ->
        Map.put(query, field, value)
      end)

    {:noreply, assign(socket, queries: queries)}
  end

  def handle_event("update_time_range", %{"value" => value}, socket) do
    {:noreply, assign(socket, time_range_value: value)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-8 bg-white rounded-lg shadow p-6">
      <h2 class="text-lg font-semibold mb-4">
        {if @action == :add_widget, do: "Add Widget", else: "Edit Widget"}
      </h2>

      <.simple_form for={@form} id="widget-form" phx-change="validate" phx-submit="save" phx-target={@myself}>
        <.input field={@form[:title]} type="text" label="Title" required />

        <.input
          field={@form[:chart_type]}
          type="select"
          label="Chart Type"
          options={[
            {"Line", "line"},
            {"Bar", "bar"},
            {"Area", "area"},
            {"Points", "points"}
          ]}
          required
        />

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Time Range</label>
          <select
            name="widget[time_range]"
            class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            phx-click="update_time_range"
            phx-target={@myself}
            value={@time_range_value}
          >
            <option value="5m" selected={@time_range_value == "5m"}>Last 5 minutes</option>
            <option value="15m" selected={@time_range_value == "15m"}>Last 15 minutes</option>
            <option value="1h" selected={@time_range_value == "1h"}>Last 1 hour</option>
            <option value="6h" selected={@time_range_value == "6h"}>Last 6 hours</option>
            <option value="24h" selected={@time_range_value == "24h"}>Last 24 hours</option>
            <option value="7d" selected={@time_range_value == "7d"}>Last 7 days</option>
          </select>
        </div>

        <div class="border-t pt-4 mt-4">
          <h3 class="text-sm font-medium text-gray-700 mb-3">Query Series</h3>

          <div :for={{query, index} <- Enum.with_index(@queries)} class="border rounded-lg p-3 mb-3 bg-gray-50">
            <div class="flex justify-between items-center mb-2">
              <span class="text-xs font-medium text-gray-500">Series {index + 1}</span>
              <button
                type="button"
                phx-click="remove_query"
                phx-value-index={index}
                phx-target={@myself}
                class="text-red-500 hover:text-red-700 text-xs"
              >
                Remove
              </button>
            </div>

            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">Device</label>
                <select
                  phx-change="select_device"
                  phx-target={@myself}
                  name={"select_device[#{index}]"}
                  class="w-full rounded-lg border border-gray-300 px-3 py-1.5 text-sm"
                >
                  <option value="">Select a device...</option>
                  <optgroup :for={{platform_label, devices} <- @device_options} label={platform_label}>
                    <option
                      :for={{hostname, id} <- devices}
                      value={id}
                      selected={query["device_id"] == id}
                    >
                      {hostname}
                    </option>
                  </optgroup>
                </select>
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">Metric Path</label>
                <select
                  phx-change="select_path"
                  phx-target={@myself}
                  name={"select_path[#{index}]"}
                  disabled={!Map.has_key?(@path_options_map, index)}
                  class="w-full rounded-lg border border-gray-300 px-3 py-1.5 text-sm disabled:bg-gray-100 disabled:text-gray-400"
                >
                  <option value="">
                    {if Map.has_key?(@path_options_map, index), do: "Select a metric path...", else: "Select a device first..."}
                  </option>
                  <optgroup
                    :for={{category_label, paths} <- Map.get(@path_options_map, index, [])}
                    label={category_label}
                  >
                    <option
                      :for={{path_label, path_value} <- paths}
                      value={path_value}
                      selected={query["path"] == path_value}
                    >
                      {path_label}
                    </option>
                  </optgroup>
                </select>
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">Label</label>
                <input
                  type="text"
                  value={query["label"] || ""}
                  phx-blur="update_query"
                  phx-value-index={index}
                  phx-value-field="label"
                  phx-target={@myself}
                  placeholder="Series label"
                  class="w-full rounded-lg border border-gray-300 px-3 py-1.5 text-sm"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">Color</label>
                <div class="flex gap-2">
                  <input
                    type="color"
                    value={query["color"] || "#3B82F6"}
                    phx-change="update_color"
                    phx-target={@myself}
                    name={"update_color[#{index}]"}
                    class="h-[34px] w-10 rounded border border-gray-300 cursor-pointer p-0.5"
                  />
                  <input
                    type="text"
                    value={query["color"] || "#3B82F6"}
                    phx-blur="update_query"
                    phx-value-index={index}
                    phx-value-field="color"
                    phx-target={@myself}
                    placeholder="#3B82F6"
                    class="flex-1 rounded-lg border border-gray-300 px-3 py-1.5 text-sm"
                  />
                </div>
              </div>
            </div>
          </div>

          <button
            type="button"
            phx-click="add_query"
            phx-target={@myself}
            class="text-indigo-600 hover:text-indigo-800 text-sm font-medium"
          >
            + Add Series
          </button>
        </div>

        <:actions>
          <.button type="submit">
            {if @action == :add_widget, do: "Create Widget", else: "Update Widget"}
          </.button>
          <.link
            patch={~p"/dashboards/#{@dashboard.id}"}
            class="ml-4 text-gray-600 hover:text-gray-800 text-sm"
          >
            Cancel
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  # --- Private helpers ---

  defp empty_query do
    %{"device_id" => "", "path" => "", "label" => "", "color" => "#3B82F6"}
  end

  defp get_time_range_duration(%{"duration" => duration}), do: duration
  defp get_time_range_duration(%{duration: duration}), do: duration
  defp get_time_range_duration(_), do: "1h"

  defp extract_indexed_param(params, key) do
    data = params[key]

    index_str =
      case params do
        %{"_target" => [^key, idx]} -> idx
        _ -> data |> Map.keys() |> hd()
      end

    {String.to_integer(index_str), Map.get(data, index_str, "")}
  end

  defp generate_widget_id do
    "wgt_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end
end

defmodule SwitchTelemetryWeb.SubscriptionLive.FormComponent do
  use SwitchTelemetryWeb, :live_component

  alias SwitchTelemetry.Collector
  alias SwitchTelemetry.Collector.SubscriptionPaths

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    available_paths = SubscriptionPaths.list_paths(assigns.device.platform)
    categories = available_paths |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(available_paths: available_paths, categories: categories, show_path_browser: false)
     |> assign_form_values()}
  end

  defp assign_form_values(socket) do
    subscription = socket.assigns.subscription

    sample_interval_ns = subscription.sample_interval_ns || 30_000_000_000
    sample_interval_seconds = div(sample_interval_ns, 1_000_000_000)

    assign(socket,
      form_values: %{
        "paths" => Enum.join(subscription.paths || [], "\n"),
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

  def handle_event("toggle_path_browser", _params, socket) do
    {:noreply, assign(socket, show_path_browser: !socket.assigns.show_path_browser)}
  end

  def handle_event("add_path", %{"path" => path}, socket) do
    current_paths = socket.assigns.form_values["paths"]

    new_paths =
      if current_paths == "" do
        path
      else
        current_paths <> "\n" <> path
      end

    form_values = Map.put(socket.assigns.form_values, "paths", new_paths)
    {:noreply, assign(socket, form_values: form_values)}
  end

  defp prepare_params(params, socket) do
    paths =
      params
      |> Map.get("paths", "")
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

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

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <.simple_form for={%{}} phx-submit="save" phx-target={@myself}>
        <.input
          type="textarea"
          name="subscription[paths]"
          label="Paths (one per line)"
          value={@form_values["paths"]}
          placeholder="/interfaces/interface/state/counters&#10;/system/state/hostname&#10;/network-instances/network-instance/protocols"
          required
          rows="6"
        />

        <div class="mb-4">
          <button
            type="button"
            phx-click="toggle_path_browser"
            phx-target={@myself}
            class="text-sm text-indigo-600 hover:text-indigo-800 flex items-center gap-1"
          >
            <span :if={!@show_path_browser}>+ Browse Paths</span>
            <span :if={@show_path_browser}>- Hide Path Browser</span>
          </button>

          <div :if={@show_path_browser} class="mt-3 border rounded-lg p-4 bg-gray-50 max-h-64 overflow-y-auto">
            <div :for={category <- @categories} class="mb-3">
              <h4 class="text-xs font-semibold text-gray-500 uppercase mb-1">{category}</h4>
              <div :for={entry <- Enum.filter(@available_paths, &(&1.category == category))} class="flex items-center justify-between py-1">
                <div>
                  <code class="text-xs text-gray-700">{entry.path}</code>
                  <span class="text-xs text-gray-400 ml-2">{entry.description}</span>
                </div>
                <button
                  type="button"
                  phx-click="add_path"
                  phx-value-path={entry.path}
                  phx-target={@myself}
                  class="text-xs text-indigo-600 hover:text-indigo-800 ml-2 whitespace-nowrap"
                >
                  + Add
                </button>
              </div>
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

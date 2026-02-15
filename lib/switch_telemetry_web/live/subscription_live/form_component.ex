defmodule SwitchTelemetryWeb.SubscriptionLive.FormComponent do
  use SwitchTelemetryWeb, :live_component

  alias SwitchTelemetry.Collector

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_form_values()}
  end

  defp assign_form_values(socket) do
    subscription = socket.assigns.subscription

    assign(socket,
      form_values: %{
        "paths" => Enum.join(subscription.paths || [], "\n"),
        "mode" => (subscription.mode && to_string(subscription.mode)) || "stream",
        "sample_interval_ns" => to_string(subscription.sample_interval_ns || 30_000_000_000),
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

  defp prepare_params(params, socket) do
    paths =
      params
      |> Map.get("paths", "")
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    enabled = Map.get(params, "enabled", "false") == "true"

    params
    |> Map.put("paths", paths)
    |> Map.put("enabled", enabled)
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
          name="subscription[sample_interval_ns]"
          label="Sample Interval (nanoseconds)"
          value={@form_values["sample_interval_ns"]}
          min="1000000000"
          step="1000000000"
        />
        <p class="text-xs text-gray-500 -mt-2 mb-4">
          Common values: 10s = 10000000000, 30s = 30000000000, 60s = 60000000000
        </p>
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

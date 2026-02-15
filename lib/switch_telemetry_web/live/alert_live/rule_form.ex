defmodule SwitchTelemetryWeb.AlertLive.RuleForm do
  use SwitchTelemetryWeb, :live_component

  alias SwitchTelemetry.Alerting
  alias SwitchTelemetry.Devices

  @impl true
  @spec mount(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(socket) do
    devices = Devices.list_devices()

    device_options =
      [{"All devices", ""}] ++
        Enum.map(devices, fn d -> {d.hostname, d.id} end)

    {:ok, assign(socket, device_options: device_options)}
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_form_values()}
  end

  defp assign_form_values(socket) do
    rule = socket.assigns.rule

    assign(socket,
      form_values: %{
        "name" => rule.name || "",
        "description" => rule.description || "",
        "device_id" => rule.device_id || "",
        "path" => rule.path || "",
        "condition" => (rule.condition && to_string(rule.condition)) || "above",
        "threshold" => (rule.threshold && to_string(rule.threshold)) || "",
        "duration_seconds" => to_string(rule.duration_seconds || 60),
        "cooldown_seconds" => to_string(rule.cooldown_seconds || 300),
        "severity" => (rule.severity && to_string(rule.severity)) || "warning"
      }
    )
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("save_rule", %{"rule" => rule_params}, socket) do
    rule_params = parse_rule_params(rule_params, socket.assigns.rule.id)

    result =
      case socket.assigns.action do
        :new_rule ->
          Alerting.create_alert_rule(rule_params)

        :edit_rule ->
          Alerting.update_alert_rule(socket.assigns.rule, rule_params)
      end

    case result do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Alert rule saved")
         |> push_navigate(to: ~p"/alerts")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save alert rule")}
    end
  end

  defp parse_rule_params(params, id) do
    params
    |> Map.put("id", id)
    |> maybe_clear_device_id()
    |> maybe_parse_threshold()
  end

  defp maybe_clear_device_id(%{"device_id" => ""} = params) do
    Map.put(params, "device_id", nil)
  end

  defp maybe_clear_device_id(params), do: params

  defp maybe_parse_threshold(%{"threshold" => ""} = params), do: params

  defp maybe_parse_threshold(%{"threshold" => val} = params) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> Map.put(params, "threshold", num)
      :error -> params
    end
  end

  defp maybe_parse_threshold(params), do: params

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <.simple_form for={%{}} phx-submit="save_rule" phx-target={@myself}>
        <.input type="text" name="rule[name]" label="Name" value={@form_values["name"]} required />
        <.input type="textarea" name="rule[description]" label="Description" value={@form_values["description"]} />
        <.input
          type="select"
          name="rule[device_id]"
          label="Device (optional)"
          options={@device_options}
          value={@form_values["device_id"]}
        />
        <.input type="text" name="rule[path]" label="Metric Path" value={@form_values["path"]} required />
        <.input
          type="select"
          name="rule[condition]"
          label="Condition"
          options={[
            {"Above", "above"},
            {"Below", "below"},
            {"Absent", "absent"},
            {"Rate Increase", "rate_increase"}
          ]}
          value={@form_values["condition"]}
          required
        />
        <.input type="number" name="rule[threshold]" label="Threshold" value={@form_values["threshold"]} />
        <.input type="number" name="rule[duration_seconds]" label="Duration (seconds)" value={@form_values["duration_seconds"]} required />
        <.input type="number" name="rule[cooldown_seconds]" label="Cooldown (seconds)" value={@form_values["cooldown_seconds"]} required />
        <.input
          type="select"
          name="rule[severity]"
          label="Severity"
          options={[
            {"Info", "info"},
            {"Warning", "warning"},
            {"Critical", "critical"}
          ]}
          value={@form_values["severity"]}
          required
        />
        <:actions>
          <.button type="submit">Save Rule</.button>
          <.link navigate={~p"/alerts"} class="ml-4 text-gray-600">Cancel</.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end

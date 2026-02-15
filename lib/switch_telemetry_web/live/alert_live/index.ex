defmodule SwitchTelemetryWeb.AlertLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Alerting
  alias SwitchTelemetry.Alerting.{AlertRule, NotificationChannel}

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "alerts")
    end

    rules = Alerting.list_alert_rules()
    events = Alerting.list_recent_events(limit: 20)
    channels = Alerting.list_channels()
    firing_rules = Enum.filter(rules, &(&1.state == :firing))

    {:ok,
     assign(socket,
       rules: rules,
       events: events,
       channels: channels,
       firing_rules: firing_rules,
       page_title: "Alerts"
     )}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Alerts")
    |> assign(:rule, nil)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :new_rule, _params) do
    socket
    |> assign(:page_title, "New Alert Rule")
    |> assign(:rule, %AlertRule{id: generate_id()})
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :edit_rule, %{"id" => id}) do
    rule = Alerting.get_alert_rule!(id)

    socket
    |> assign(:page_title, "Edit Alert Rule")
    |> assign(:rule, rule)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :channels, _params) do
    socket
    |> assign(:page_title, "Notification Channels")
    |> assign(:rule, nil)
    |> assign(:channel, nil)
  end

  defp apply_action(socket, :new_channel, _params) do
    socket
    |> assign(:page_title, "New Channel")
    |> assign(:rule, nil)
    |> assign(:channel, %NotificationChannel{id: generate_id()})
  end

  defp apply_action(socket, :edit_channel, %{"id" => id}) do
    channel = Alerting.get_channel!(id)

    socket
    |> assign(:page_title, "Edit Channel")
    |> assign(:rule, nil)
    |> assign(:channel, channel)
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    rule = Alerting.get_alert_rule!(id)
    {:ok, _updated} = Alerting.update_alert_rule(rule, %{enabled: !rule.enabled})
    rules = Alerting.list_alert_rules()
    firing_rules = Enum.filter(rules, &(&1.state == :firing))
    {:noreply, assign(socket, rules: rules, firing_rules: firing_rules)}
  end

  def handle_event("delete_rule", %{"id" => id}, socket) do
    rule = Alerting.get_alert_rule!(id)
    {:ok, _} = Alerting.delete_alert_rule(rule)
    rules = Alerting.list_alert_rules()
    firing_rules = Enum.filter(rules, &(&1.state == :firing))

    {:noreply,
     socket
     |> assign(rules: rules, firing_rules: firing_rules)
     |> put_flash(:info, "Rule deleted")}
  end

  def handle_event("acknowledge", %{"id" => id}, socket) do
    rule = Alerting.get_alert_rule!(id)
    {:ok, _} = Alerting.update_rule_state(rule, :acknowledged)
    rules = Alerting.list_alert_rules()
    firing_rules = Enum.filter(rules, &(&1.state == :firing))
    {:noreply, assign(socket, rules: rules, firing_rules: firing_rules)}
  end

  def handle_event("delete_channel", %{"id" => id}, socket) do
    channel = Alerting.get_channel!(id)
    {:ok, _} = Alerting.delete_channel(channel)

    {:noreply,
     socket
     |> assign(channels: Alerting.list_channels())
     |> put_flash(:info, "Channel deleted")}
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:alert_event, _event}, socket) do
    rules = Alerting.list_alert_rules()
    events = Alerting.list_recent_events(limit: 20)
    firing_rules = Enum.filter(rules, &(&1.state == :firing))
    {:noreply, assign(socket, rules: rules, events: events, firing_rules: firing_rules)}
  end

  def handle_info({:rule_updated, _rule}, socket) do
    rules = Alerting.list_alert_rules()
    firing_rules = Enum.filter(rules, &(&1.state == :firing))
    {:noreply, assign(socket, rules: rules, firing_rules: firing_rules)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <header class="flex justify-between items-center mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Alerts</h1>
        <div class="flex gap-2">
          <.link
            navigate={~p"/alerts/channels"}
            class="bg-gray-100 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-200 text-sm font-medium"
          >
            Channels
          </.link>
          <.link
            navigate={~p"/alerts/rules/new"}
            class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 text-sm font-medium"
          >
            New Rule
          </.link>
        </div>
      </header>

      <%= if @live_action in [:new_rule, :edit_rule] do %>
        <div class="mb-8 bg-white rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">
            {if @live_action == :new_rule, do: "Create Alert Rule", else: "Edit Alert Rule"}
          </h2>
          <.live_component
            module={SwitchTelemetryWeb.AlertLive.RuleForm}
            id={@rule.id || "new"}
            rule={@rule}
            action={@live_action}
          />
        </div>
      <% end %>

      <%= if @live_action in [:channels, :new_channel, :edit_channel] do %>
        <div class="mb-8">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-lg font-semibold text-gray-900">Notification Channels</h2>
            <.link
              navigate={~p"/alerts/channels/new"}
              class="bg-indigo-600 text-white px-3 py-1.5 rounded-lg hover:bg-indigo-700 text-sm font-medium"
            >
              New Channel
            </.link>
          </div>

          <%= if @live_action in [:new_channel, :edit_channel] do %>
            <div class="mb-6 bg-white rounded-lg shadow p-6">
              <h3 class="text-md font-semibold mb-4">
                {if @live_action == :new_channel, do: "Create Channel", else: "Edit Channel"}
              </h3>
              <.live_component
                module={SwitchTelemetryWeb.AlertLive.ChannelForm}
                id={@channel.id || "new"}
                channel={@channel}
                action={@live_action}
              />
            </div>
          <% end %>

          <div class="bg-white rounded-lg shadow overflow-hidden">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Enabled</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <tr :for={channel <- @channels} class="hover:bg-gray-50">
                  <td class="px-6 py-4 text-sm font-medium text-gray-900">{channel.name}</td>
                  <td class="px-6 py-4 text-sm text-gray-500">{channel.type}</td>
                  <td class="px-6 py-4">
                    <span class={"inline-flex px-2 py-1 text-xs rounded-full #{if channel.enabled, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                      {if channel.enabled, do: "Yes", else: "No"}
                    </span>
                  </td>
                  <td class="px-6 py-4 text-right space-x-2">
                    <.link navigate={~p"/alerts/channels/#{channel.id}/edit"} class="text-sm text-indigo-600 hover:text-indigo-800">
                      Edit
                    </.link>
                    <button
                      phx-click="delete_channel"
                      phx-value-id={channel.id}
                      data-confirm="Delete this channel?"
                      class="text-sm text-red-600 hover:text-red-800"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <div :if={@channels == []} class="text-center py-8 text-gray-500 text-sm">
              No notification channels configured.
            </div>
          </div>

          <div class="mt-4">
            <.link navigate={~p"/alerts"} class="text-sm text-indigo-600 hover:text-indigo-800">
              Back to Alerts
            </.link>
          </div>
        </div>
      <% else %>
        <%!-- Active Alerts Panel --%>
        <div class="mb-8" id="active-alerts">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Active Alerts</h2>
          <div :if={@firing_rules == []} class="bg-green-50 rounded-lg p-4 text-green-800 text-sm">
            No active alerts. All clear.
          </div>
          <div :if={@firing_rules != []} class="space-y-3">
            <div :for={rule <- @firing_rules} class="bg-white rounded-lg shadow p-4 flex items-center justify-between border-l-4 border-red-500">
              <div class="flex items-center gap-3">
                <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full #{severity_color(rule.severity)}"}>
                  {rule.severity}
                </span>
                <div>
                  <p class="font-medium text-gray-900">{rule.name}</p>
                  <p class="text-sm text-gray-500">{rule.path} {rule.condition} {rule.threshold}</p>
                </div>
              </div>
              <button
                phx-click="acknowledge"
                phx-value-id={rule.id}
                class="bg-yellow-100 text-yellow-800 px-3 py-1 rounded text-sm hover:bg-yellow-200"
              >
                Acknowledge
              </button>
            </div>
          </div>
        </div>

        <%!-- Alert Rules Panel --%>
        <div class="mb-8" id="alert-rules">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Alert Rules</h2>
          <div class="bg-white rounded-lg shadow overflow-hidden">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Path</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Condition</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Severity</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">State</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Enabled</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <tr :for={rule <- @rules} class="hover:bg-gray-50">
                  <td class="px-6 py-4 text-sm font-medium text-gray-900">{rule.name}</td>
                  <td class="px-6 py-4 text-sm text-gray-500 font-mono">{rule.path}</td>
                  <td class="px-6 py-4 text-sm text-gray-500">{rule.condition} {rule.threshold}</td>
                  <td class="px-6 py-4">
                    <span class={"inline-flex px-2 py-1 text-xs rounded-full #{severity_color(rule.severity)}"}>
                      {rule.severity}
                    </span>
                  </td>
                  <td class="px-6 py-4">
                    <span class={"inline-flex px-2 py-1 text-xs rounded-full #{state_color(rule.state)}"}>
                      {rule.state}
                    </span>
                  </td>
                  <td class="px-6 py-4">
                    <button
                      phx-click="toggle_enabled"
                      phx-value-id={rule.id}
                      class={"relative inline-flex h-6 w-11 items-center rounded-full #{if rule.enabled, do: "bg-indigo-600", else: "bg-gray-200"}"}
                    >
                      <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition #{if rule.enabled, do: "translate-x-6", else: "translate-x-1"}"} />
                    </button>
                  </td>
                  <td class="px-6 py-4 text-right space-x-2">
                    <.link navigate={~p"/alerts/rules/#{rule.id}/edit"} class="text-sm text-indigo-600 hover:text-indigo-800">
                      Edit
                    </.link>
                    <button
                      phx-click="delete_rule"
                      phx-value-id={rule.id}
                      data-confirm="Delete this rule?"
                      class="text-sm text-red-600 hover:text-red-800"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <div :if={@rules == []} class="text-center py-8 text-gray-500 text-sm">
              No alert rules configured.
            </div>
          </div>
        </div>

        <%!-- Recent Events Panel --%>
        <div id="recent-events">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Recent Events</h2>
          <div class="bg-white rounded-lg shadow overflow-hidden">
            <div :if={@events == []} class="text-center py-8 text-gray-500 text-sm">
              No alert events recorded.
            </div>
            <div :if={@events != []} class="divide-y divide-gray-200">
              <div :for={event <- @events} class="px-6 py-3 flex items-center gap-3">
                <span class={"inline-flex w-2 h-2 rounded-full #{event_status_color(event.status)}"} />
                <span class="text-sm text-gray-500 w-28 shrink-0">{format_timestamp(event.inserted_at)}</span>
                <span class="text-sm font-medium text-gray-900">{event.status}</span>
                <span :if={event.value} class="text-sm text-gray-500">value: {event.value}</span>
                <span :if={event.message} class="text-sm text-gray-400 truncate">{event.message}</span>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp severity_color(:critical), do: "bg-red-100 text-red-800"
  defp severity_color(:warning), do: "bg-yellow-100 text-yellow-800"
  defp severity_color(:info), do: "bg-blue-100 text-blue-800"
  defp severity_color(_), do: "bg-gray-100 text-gray-800"

  defp state_color(:firing), do: "bg-red-100 text-red-800"
  defp state_color(:acknowledged), do: "bg-yellow-100 text-yellow-800"
  defp state_color(:ok), do: "bg-green-100 text-green-800"
  defp state_color(_), do: "bg-gray-100 text-gray-800"

  defp event_status_color(:firing), do: "bg-red-500"
  defp event_status_color(:resolved), do: "bg-green-500"
  defp event_status_color(:acknowledged), do: "bg-yellow-500"
  defp event_status_color(_), do: "bg-gray-400"

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp generate_id do
    Ecto.UUID.generate()
  end
end

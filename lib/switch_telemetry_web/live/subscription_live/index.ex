defmodule SwitchTelemetryWeb.SubscriptionLive.Index do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.{Collector, Devices}
  alias SwitchTelemetry.Collector.Subscription

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => device_id}, _session, socket) do
    device = Devices.get_device!(device_id)
    subscriptions = Collector.list_subscriptions_for_device(device_id)

    {:ok,
     assign(socket,
       device: device,
       subscriptions: subscriptions,
       page_title: "#{device.hostname} - Subscriptions"
     )}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Subscription - #{socket.assigns.device.hostname}")
    |> assign(:subscription, %Subscription{
      id: generate_id(),
      device_id: socket.assigns.device.id,
      paths: [],
      mode: :stream,
      sample_interval_ns: 30_000_000_000,
      encoding: :proto,
      enabled: true
    })
  end

  defp apply_action(socket, :edit, %{"subscription_id" => subscription_id}) do
    subscription = Collector.get_subscription!(subscription_id)

    socket
    |> assign(:page_title, "Edit Subscription - #{socket.assigns.device.hostname}")
    |> assign(:subscription, subscription)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "#{socket.assigns.device.hostname} - Subscriptions")
    |> assign(:subscription, nil)
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("toggle", %{"id" => id}, socket) do
    subscription = Collector.get_subscription!(id)
    {:ok, _updated} = Collector.toggle_subscription(subscription)
    subscriptions = Collector.list_subscriptions_for_device(socket.assigns.device.id)
    {:noreply, assign(socket, subscriptions: subscriptions)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    subscription = Collector.get_subscription!(id)
    {:ok, _} = Collector.delete_subscription(subscription)
    subscriptions = Collector.list_subscriptions_for_device(socket.assigns.device.id)

    {:noreply,
     socket
     |> put_flash(:info, "Subscription deleted")
     |> assign(subscriptions: subscriptions)}
  end

  @impl true
  def handle_info({:enumerate_result, component_id, result}, socket) do
    send_update(SwitchTelemetryWeb.SubscriptionLive.FormComponent,
      id: component_id,
      enumerate_result: result
    )

    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.link navigate={~p"/devices/#{@device.id}"} class="text-sm text-gray-500 hover:text-gray-700">
        &larr; {@device.hostname}
      </.link>

      <header class="flex justify-between items-center mb-8 mt-4">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Subscriptions</h1>
          <p class="text-sm text-gray-500">{@device.hostname} ({@device.ip_address})</p>
        </div>
        <.link
          navigate={~p"/devices/#{@device.id}/subscriptions/new"}
          class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700"
        >
          New Subscription
        </.link>
      </header>

      <%= if @live_action in [:new, :edit] do %>
        <div class="mb-8 bg-white rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">
            {if @live_action == :new, do: "New Subscription", else: "Edit Subscription"}
          </h2>
          <.live_component
            module={SwitchTelemetryWeb.SubscriptionLive.FormComponent}
            id={@subscription.id || :new}
            device={@device}
            subscription={@subscription}
            action={@live_action}
          />
        </div>
      <% end %>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Paths</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Mode</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Interval</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Encoding</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={subscription <- @subscriptions} class="hover:bg-gray-50">
              <td class="px-6 py-4 text-sm">
                <div class="space-y-1">
                  <div
                    :for={path <- Enum.take(subscription.paths, 3)}
                    class="font-mono text-xs text-gray-700 truncate max-w-md"
                    title={path}
                  >
                    {path}
                  </div>
                  <div :if={length(subscription.paths) > 3} class="text-xs text-gray-400">
                    +{length(subscription.paths) - 3} more
                  </div>
                </div>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">{subscription.mode}</td>
              <td class="px-6 py-4 text-sm text-gray-500">{format_interval(subscription.sample_interval_ns)}</td>
              <td class="px-6 py-4 text-sm text-gray-500">{subscription.encoding}</td>
              <td class="px-6 py-4">
                <button
                  phx-click="toggle"
                  phx-value-id={subscription.id}
                  class={"inline-flex px-2 py-1 text-xs rounded-full cursor-pointer #{if subscription.enabled, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}
                >
                  {if subscription.enabled, do: "Enabled", else: "Disabled"}
                </button>
              </td>
              <td class="px-6 py-4 text-right space-x-2">
                <.link
                  navigate={~p"/devices/#{@device.id}/subscriptions/#{subscription.id}/edit"}
                  class="text-sm text-indigo-600 hover:text-indigo-800"
                >
                  Edit
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={subscription.id}
                  data-confirm="Delete this subscription?"
                  class="text-sm text-red-600 hover:text-red-800"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@subscriptions == []} class="text-center py-12 text-gray-500">
        No subscriptions configured for this device.
        <.link navigate={~p"/devices/#{@device.id}/subscriptions/new"} class="text-indigo-600 hover:text-indigo-800 ml-1">
          Create one
        </.link>
      </div>
    </div>
    """
  end

  defp format_interval(ns) when is_integer(ns) do
    seconds = div(ns, 1_000_000_000)

    cond do
      seconds >= 60 -> "#{div(seconds, 60)}m"
      true -> "#{seconds}s"
    end
  end

  defp format_interval(_), do: "-"

  defp generate_id do
    "sub_" <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end
end

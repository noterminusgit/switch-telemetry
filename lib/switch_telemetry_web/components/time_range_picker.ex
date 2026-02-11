defmodule SwitchTelemetryWeb.Components.TimeRangePicker do
  @moduledoc """
  LiveComponent that renders a time range picker with relative presets
  and a custom absolute range form.

  ## Assigns

    * `:id` - required component id
    * `:selected` - the current time range map, e.g. `%{"type" => "relative", "duration" => "1h"}`

  Sends `{:time_range_changed, time_range}` to the parent LiveView when the
  user selects a preset or submits a custom range.
  """
  use SwitchTelemetryWeb, :live_component

  @presets [
    {"5m", "5 min"},
    {"15m", "15 min"},
    {"1h", "1 hour"},
    {"6h", "6 hours"},
    {"24h", "24 hours"},
    {"7d", "7 days"}
  ]

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:selected, fn -> %{"type" => "relative", "duration" => "1h"} end)
      |> assign(:presets, @presets)
      |> assign_new(:show_custom, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_preset", %{"duration" => duration}, socket) do
    time_range = %{"type" => "relative", "duration" => duration}
    send(self(), {:time_range_changed, time_range})
    {:noreply, assign(socket, selected: time_range, show_custom: false)}
  end

  def handle_event("toggle_custom", _params, socket) do
    {:noreply, assign(socket, show_custom: !socket.assigns.show_custom)}
  end

  def handle_event("apply_custom", %{"start" => start_str, "end" => end_str}, socket) do
    time_range = %{"type" => "absolute", "start" => start_str, "end" => end_str}
    send(self(), {:time_range_changed, time_range})
    {:noreply, assign(socket, selected: time_range, show_custom: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <%= for {duration, label} <- @presets do %>
        <button
          type="button"
          phx-click="select_preset"
          phx-value-duration={duration}
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded border",
            if(preset_selected?(@selected, duration),
              do: "bg-indigo-600 text-white border-indigo-600",
              else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
            )
          ]}
        >
          {label}
        </button>
      <% end %>
      <button
        type="button"
        phx-click="toggle_custom"
        phx-target={@myself}
        class={[
          "px-2 py-1 text-xs rounded border",
          if(@selected["type"] == "absolute",
            do: "bg-indigo-600 text-white border-indigo-600",
            else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
          )
        ]}
      >
        Custom
      </button>
      <div :if={@show_custom} class="w-full mt-2">
        <form phx-submit="apply_custom" phx-target={@myself} class="flex items-end gap-2">
          <div>
            <label class="block text-xs text-gray-500">Start</label>
            <input type="datetime-local" name="start" required class="text-sm border rounded px-2 py-1" />
          </div>
          <div>
            <label class="block text-xs text-gray-500">End</label>
            <input type="datetime-local" name="end" required class="text-sm border rounded px-2 py-1" />
          </div>
          <button type="submit" class="bg-indigo-600 text-white px-3 py-1 rounded text-sm">Apply</button>
        </form>
      </div>
    </div>
    """
  end

  defp preset_selected?(%{"type" => "relative", "duration" => d}, duration), do: d == duration
  defp preset_selected?(_, _), do: false
end

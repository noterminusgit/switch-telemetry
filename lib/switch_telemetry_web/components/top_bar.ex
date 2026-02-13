defmodule SwitchTelemetryWeb.Components.TopBar do
  @moduledoc """
  Top bar component with hamburger menu for mobile and user info.
  """
  use SwitchTelemetryWeb, :html

  attr :current_user, :map, required: true
  attr :on_menu_click, Phoenix.LiveView.JS, default: %Phoenix.LiveView.JS{}

  def top_bar(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 flex h-16 shrink-0 items-center gap-x-4 border-b border-gray-200 bg-white px-4 shadow-sm sm:gap-x-6 sm:px-6 lg:px-8">
      <button
        type="button"
        class="md:hidden -m-2.5 p-2.5 text-gray-700"
        phx-click={@on_menu_click}
      >
        <span class="sr-only">Open sidebar</span>
        <.icon name="hero-bars-3" class="h-6 w-6" />
      </button>

      <div class="h-6 w-px bg-gray-200 md:hidden" aria-hidden="true"></div>

      <div class="flex flex-1 gap-x-4 self-stretch lg:gap-x-6">
        <div class="flex flex-1"></div>
        <div class="flex items-center gap-x-4 lg:gap-x-6">
          <div :if={@current_user} class="flex items-center gap-x-4">
            <span class="text-sm text-gray-500">{@current_user.email}</span>
            <a
              href={~p"/users/log_out"}
              data-method="delete"
              class="text-sm font-medium text-gray-700 hover:text-gray-900"
            >
              Log out
            </a>
          </div>
          <div :if={!@current_user} class="flex items-center">
            <a
              href={~p"/users/log_in"}
              class="text-sm font-medium text-gray-700 hover:text-gray-900"
            >
              Log in
            </a>
          </div>
        </div>
      </div>
    </header>
    """
  end
end

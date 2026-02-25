defmodule SwitchTelemetryWeb.Components.Sidebar do
  @moduledoc """
  Sidebar navigation component with responsive behavior.

  - 240px on desktop
  - 64px icons-only on tablet
  - Hidden on mobile (use mobile_nav instead)
  """
  use SwitchTelemetryWeb, :html

  alias SwitchTelemetryWeb.Components.NavItems

  attr :current_user, :map, required: true
  attr :current_path, :string, required: true

  def sidebar(assigns) do
    assigns = assign(assigns, :nav_items, NavItems.items())
    assigns = assign(assigns, :admin_item, NavItems.admin_item())

    ~H"""
    <aside class="hidden md:flex md:flex-shrink-0">
      <div class="flex flex-col w-16 lg:w-60 transition-all duration-300">
        <div class="flex flex-col flex-grow bg-gray-900 pt-5 pb-4 overflow-y-auto">
          <div class="flex items-center flex-shrink-0 px-4">
            <span class="hidden lg:block text-white font-semibold text-lg">Switch Telemetry</span>
            <span class="lg:hidden text-white font-bold text-xl">ST</span>
          </div>
          <nav class="mt-8 flex-1 flex flex-col space-y-1 px-2" aria-label="Sidebar">
            <.nav_item
              :for={item <- @nav_items}
              path={item.path}
              current_path={@current_path}
              icon={item.icon}
              label={item.label}
            />
            <.nav_item
              :if={@current_user.role == :admin}
              path={@admin_item.path}
              current_path={@current_path}
              icon={@admin_item.icon}
              label={@admin_item.label}
              admin={true}
            />
          </nav>
        </div>
      </div>
    </aside>
    """
  end

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :admin, :boolean, default: false

  defp nav_item(assigns) do
    active = String.starts_with?(assigns.current_path, assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@path}
      class={[
        "group flex items-center px-2 py-2 text-sm font-medium rounded-md transition-colors",
        @active && "bg-gray-800 text-white",
        !@active && "text-gray-300 hover:bg-gray-700 hover:text-white",
        @admin && "mt-auto"
      ]}
      aria-current={@active && "page"}
    >
      <.icon
        name={@icon}
        class={[
          "flex-shrink-0 h-6 w-6 lg:mr-3",
          @active && "text-white",
          !@active && "text-gray-400 group-hover:text-gray-300"
        ]}
      />
      <span class="hidden lg:inline">{@label}</span>
    </a>
    """
  end
end

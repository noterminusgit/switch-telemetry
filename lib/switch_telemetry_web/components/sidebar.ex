defmodule SwitchTelemetryWeb.Components.Sidebar do
  @moduledoc """
  Sidebar navigation component with responsive behavior.

  - 240px on desktop
  - 64px icons-only on tablet
  - Hidden on mobile (use mobile_nav instead)
  """
  use SwitchTelemetryWeb, :html

  attr :current_user, :map, required: true
  attr :current_path, :string, required: true

  def sidebar(assigns) do
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
              path={~p"/dashboards"}
              current_path={@current_path}
              icon="hero-chart-bar-square"
              label="Dashboards"
            />
            <.nav_item
              path={~p"/devices"}
              current_path={@current_path}
              icon="hero-server-stack"
              label="Devices"
            />
            <.nav_item
              path={~p"/streams"}
              current_path={@current_path}
              icon="hero-signal"
              label="Streams"
            />
            <.nav_item
              path={~p"/alerts"}
              current_path={@current_path}
              icon="hero-bell-alert"
              label="Alerts"
            />
            <.nav_item
              path={~p"/credentials"}
              current_path={@current_path}
              icon="hero-key"
              label="Credentials"
            />
            <.nav_item
              path={~p"/settings"}
              current_path={@current_path}
              icon="hero-cog-6-tooth"
              label="Settings"
            />
            <.nav_item
              :if={@current_user.role == :admin}
              path={~p"/admin/users"}
              current_path={@current_path}
              icon="hero-users"
              label="Users"
              admin={true}
            />
            <.nav_item
              :if={@current_user.role == :admin}
              path={~p"/admin/admin_emails"}
              current_path={@current_path}
              icon="hero-envelope"
              label="Admin Emails"
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

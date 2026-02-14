defmodule SwitchTelemetryWeb.Components.MobileNav do
  @moduledoc """
  Mobile navigation drawer component.

  Slide-out drawer with backdrop overlay.
  Closes on link click or backdrop click.
  """
  use SwitchTelemetryWeb, :html

  attr :id, :string, default: "mobile-nav"
  attr :current_user, :map, required: true
  attr :current_path, :string, required: true

  def mobile_nav(assigns) do
    ~H"""
    <div id={@id} class="relative z-50 hidden md:hidden" role="dialog" aria-modal="true">
      <div
        id={"#{@id}-backdrop"}
        class="fixed inset-0 bg-gray-900/80"
        phx-click={hide_mobile_nav(@id)}
      >
      </div>

      <div class="fixed inset-0 flex">
        <div
          id={"#{@id}-panel"}
          class="relative mr-16 flex w-full max-w-xs flex-1"
        >
          <div class="absolute left-full top-0 flex w-16 justify-center pt-5">
            <button type="button" class="-m-2.5 p-2.5" phx-click={hide_mobile_nav(@id)}>
              <span class="sr-only">Close sidebar</span>
              <.icon name="hero-x-mark" class="h-6 w-6 text-white" />
            </button>
          </div>

          <div class="flex grow flex-col gap-y-5 overflow-y-auto bg-gray-900 px-6 pb-4">
            <div class="flex h-16 shrink-0 items-center">
              <span class="text-white font-semibold text-lg">Switch Telemetry</span>
            </div>
            <nav class="flex flex-1 flex-col">
              <ul role="list" class="flex flex-1 flex-col gap-y-7">
                <li>
                  <ul role="list" class="-mx-2 space-y-1">
                    <.mobile_nav_item
                      path={~p"/dashboards"}
                      current_path={@current_path}
                      icon="hero-chart-bar-square"
                      label="Dashboards"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      path={~p"/devices"}
                      current_path={@current_path}
                      icon="hero-server-stack"
                      label="Devices"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      path={~p"/streams"}
                      current_path={@current_path}
                      icon="hero-signal"
                      label="Streams"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      path={~p"/alerts"}
                      current_path={@current_path}
                      icon="hero-bell-alert"
                      label="Alerts"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      path={~p"/credentials"}
                      current_path={@current_path}
                      icon="hero-key"
                      label="Credentials"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      path={~p"/settings"}
                      current_path={@current_path}
                      icon="hero-cog-6-tooth"
                      label="Settings"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      :if={@current_user.role == :admin}
                      path={~p"/admin/users"}
                      current_path={@current_path}
                      icon="hero-users"
                      label="Users"
                      nav_id={@id}
                    />
                    <.mobile_nav_item
                      :if={@current_user.role == :admin}
                      path={~p"/admin/admin_emails"}
                      current_path={@current_path}
                      icon="hero-envelope"
                      label="Admin Emails"
                      nav_id={@id}
                    />
                  </ul>
                </li>
              </ul>
            </nav>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :nav_id, :string, required: true

  defp mobile_nav_item(assigns) do
    active = String.starts_with?(assigns.current_path, assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <li>
      <a
        href={@path}
        phx-click={hide_mobile_nav(@nav_id)}
        class={[
          "group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6",
          @active && "bg-gray-800 text-white",
          !@active && "text-gray-400 hover:bg-gray-800 hover:text-white"
        ]}
      >
        <.icon
          name={@icon}
          class={[
            "h-6 w-6 shrink-0",
            @active && "text-white",
            !@active && "text-gray-400 group-hover:text-white"
          ]}
        />
        {@label}
      </a>
    </li>
    """
  end

  @doc """
  Shows the mobile navigation drawer.
  """
  def show_mobile_nav(id) do
    JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-backdrop",
      time: 300,
      transition: {"transition-opacity ease-linear duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-panel",
      time: 300,
      transition:
        {"transition ease-in-out duration-300 transform", "-translate-x-full", "translate-x-0"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
  end

  @doc """
  Hides the mobile navigation drawer.
  """
  def hide_mobile_nav(id) do
    JS.hide(
      to: "##{id}-backdrop",
      time: 300,
      transition: {"transition-opacity ease-linear duration-300", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-panel",
      time: 300,
      transition:
        {"transition ease-in-out duration-300 transform", "translate-x-0", "-translate-x-full"}
    )
    |> JS.hide(to: "##{id}", time: 300)
    |> JS.remove_class("overflow-hidden", to: "body")
  end
end

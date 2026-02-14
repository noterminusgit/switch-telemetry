defmodule SwitchTelemetryWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  use Gettext, backend: SwitchTelemetryWeb.Gettext

  @doc """
  Renders a slide-over modal panel.

  ## Examples

      <.modal id="confirm-modal" show={@show_modal} on_cancel={JS.push("close_modal")}>
        <:title>Confirm Action</:title>
        <p>Are you sure?</p>
        <:actions>
          <.button>Confirm</.button>
        </:actions>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  slot :inner_block, required: true
  slot :title
  slot :subtitle
  slot :actions

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-gray-900/50 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-hidden"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="absolute inset-0 overflow-hidden">
          <div class="pointer-events-none fixed inset-y-0 right-0 flex max-w-full pl-10">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="pointer-events-auto w-screen max-w-md"
            >
              <div class="flex h-full flex-col overflow-y-scroll bg-white shadow-xl">
                <div class="bg-indigo-700 px-4 py-6 sm:px-6">
                  <div class="flex items-center justify-between">
                    <h2
                      :if={@title != []}
                      id={"#{@id}-title"}
                      class="text-base font-semibold leading-6 text-white"
                    >
                      {render_slot(@title)}
                    </h2>
                    <div class="ml-3 flex h-7 items-center">
                      <button
                        type="button"
                        class="relative rounded-md bg-indigo-700 text-indigo-200 hover:text-white focus:outline-none focus:ring-2 focus:ring-white"
                        phx-click={JS.exec("data-cancel", to: "##{@id}")}
                      >
                        <span class="sr-only">Close panel</span>
                        <.icon name="hero-x-mark" class="h-6 w-6" />
                      </button>
                    </div>
                  </div>
                  <div :if={@subtitle != []} class="mt-1">
                    <p id={"#{@id}-description"} class="text-sm text-indigo-300">
                      {render_slot(@subtitle)}
                    </p>
                  </div>
                </div>
                <div class="relative flex-1 px-4 py-6 sm:px-6">
                  {render_slot(@inner_block)}
                </div>
                <div :if={@actions != []} class="flex flex-shrink-0 justify-end gap-3 px-4 py-4 border-t border-gray-200">
                  {render_slot(@actions)}
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a Heroicon.

  Heroicons come in three styles - outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a dropdown menu.

  ## Examples

      <.dropdown id="user-menu">
        <:trigger>
          <.button>Options</.button>
        </:trigger>
        <:item navigate={~p"/settings"}>Settings</:item>
        <:item phx-click="logout">Log out</:item>
      </.dropdown>
  """
  attr :id, :string, required: true

  slot :trigger, required: true

  slot :item do
    attr :navigate, :string
    attr :href, :string
    attr :method, :string
  end

  def dropdown(assigns) do
    ~H"""
    <div id={@id} class="relative" phx-click-away={hide_dropdown(@id)}>
      <div phx-click={toggle_dropdown(@id)}>
        {render_slot(@trigger)}
      </div>
      <div
        id={"#{@id}-menu"}
        class="hidden absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none"
        role="menu"
        aria-orientation="vertical"
        aria-labelledby={"#{@id}-button"}
        tabindex="-1"
      >
        <.link
          :for={item <- @item}
          navigate={item[:navigate]}
          href={item[:href]}
          method={item[:method]}
          class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
          role="menuitem"
          tabindex="-1"
        >
          {render_slot(item)}
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders a tab navigation component.

  ## Examples

      <.tabs id="device-tabs" active_tab={@active_tab}>
        <:tab id="overview" label="Overview" />
        <:tab id="metrics" label="Metrics" />
        <:tab id="settings" label="Settings" />
      </.tabs>
  """
  attr :id, :string, required: true
  attr :active_tab, :string, required: true

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
    attr :navigate, :string
    attr :patch, :string
  end

  def tabs(assigns) do
    ~H"""
    <div id={@id} class="border-b border-gray-200">
      <nav class="-mb-px flex space-x-8" aria-label="Tabs">
        <.link
          :for={tab <- @tab}
          navigate={tab[:navigate]}
          patch={tab[:patch]}
          class={[
            "whitespace-nowrap border-b-2 py-4 px-1 text-sm font-medium",
            @active_tab == tab.id && "border-indigo-500 text-indigo-600",
            @active_tab != tab.id && "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700"
          ]}
          aria-current={@active_tab == tab.id && "page"}
        >
          {tab.label}
        </.link>
      </nav>
    </div>
    """
  end

  @doc """
  Renders a status badge.

  ## Examples

      <.status_badge status={:active} />
      <.status_badge status={:unreachable} />
  """
  attr :status, :atom, required: true, values: [:active, :inactive, :unreachable, :maintenance]
  attr :class, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      @status == :active && "bg-green-100 text-green-800",
      @status == :inactive && "bg-gray-100 text-gray-800",
      @status == :unreachable && "bg-red-100 text-red-800",
      @status == :maintenance && "bg-yellow-100 text-yellow-800",
      @class
    ]}>
      <svg
        class={[
          "-ml-0.5 mr-1.5 h-2 w-2",
          @status == :active && "fill-green-500",
          @status == :inactive && "fill-gray-400",
          @status == :unreachable && "fill-red-500",
          @status == :maintenance && "fill-yellow-500"
        ]}
        viewBox="0 0 6 6"
        aria-hidden="true"
      >
        <circle cx="3" cy="3" r="3" />
      </svg>
      {status_label(@status)}
    </span>
    """
  end

  defp status_label(:active), do: "Active"
  defp status_label(:inactive), do: "Inactive"
  defp status_label(:unreachable), do: "Unreachable"
  defp status_label(:maintenance), do: "Maintenance"

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and aria attributes"
  attr :title, :string, default: nil

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 ring-rose-500 fill-rose-900"
      ]}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a simple form.
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "additional HTML attributes"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-4">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-4 flex items-center gap-4">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any, default: nil

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file hidden month number password range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct"
  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block text-sm font-medium text-gray-700 mb-1">{@label}</label>
      <select id={@id} name={@name} class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" multiple={@multiple} {@rest}>
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <p :for={msg <- @errors} class="mt-1 text-sm text-red-600">{msg}</p>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block text-sm font-medium text-gray-700 mb-1">{@label}</label>
      <textarea id={@id} name={@name} class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <p :for={msg <- @errors} class="mt-1 text-sm text-red-600">{msg}</p>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block text-sm font-medium text-gray-700 mb-1">{@label}</label>
      <input type={@type} name={@name} id={@id} value={Phoenix.HTML.Form.normalize_value(@type, @value)} class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" {@rest} />
      <p :for={msg <- @errors} class="mt-1 text-sm text-red-600">{msg}</p>
    </div>
    """
  end

  @doc """
  Renders a button.
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 text-sm font-medium",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  defp hide(js, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  defp show_modal(id) do
    JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-opacity ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      time: 300,
      transition:
        {"transition-transform ease-out duration-300", "translate-x-full", "translate-x-0"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  defp hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      time: 200,
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-transform ease-in duration-200", "translate-x-0", "translate-x-full"}
    )
    |> JS.hide(to: "##{id}", time: 200)
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  defp toggle_dropdown(id) do
    JS.toggle(
      to: "##{id}-menu",
      in:
        {"transition ease-out duration-100", "transform opacity-0 scale-95",
         "transform opacity-100 scale-100"},
      out:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end

  defp hide_dropdown(id) do
    JS.hide(
      to: "##{id}-menu",
      transition:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end
end

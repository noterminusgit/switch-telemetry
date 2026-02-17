defmodule SwitchTelemetryWeb.UserLive.Settings do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetry.Settings

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    smtp_settings = Settings.get_smtp_settings()
    smtp_changeset = Settings.change_smtp_settings(smtp_settings)

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:email_form, to_form(email_changeset))
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:smtp_settings, smtp_settings)
     |> assign(:smtp_form, to_form(smtp_changeset))}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Account Settings
      <:subtitle>Manage your email address and password</:subtitle>
    </.header>

    <div class="space-y-12 divide-y max-w-xl mx-auto">
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input field={@email_form[:email]} type="email" label="Email" required />
          <.input
            field={@email_form[:current_password]}
            name="current_password"
            id="current_password_for_email"
            type="password"
            label="Current password"
            value=""
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Change Email</.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@password_form}
          id="password_form"
          phx-change="validate_password"
          phx-submit="update_password"
        >
          <.input field={@password_form[:password]} type="password" label="New password" required />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            id="current_password_for_password"
            type="password"
            label="Current password"
            value=""
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Change Password</.button>
          </:actions>
        </.simple_form>
      </div>
      <div :if={@current_user.role == :admin}>
        <h2 class="text-lg font-semibold text-gray-900 pt-8 mb-4">Email Configuration</h2>
        <p class="text-sm text-gray-500 mb-6">
          Configure SMTP settings for outgoing emails (magic links, alerts, password resets).
        </p>
        <.simple_form
          for={@smtp_form}
          id="smtp_form"
          phx-change="validate_smtp"
          phx-submit="update_smtp"
        >
          <div class="flex items-center gap-4 mb-4">
            <.input field={@smtp_form[:enabled]} type="checkbox" label="Enable SMTP" />
          </div>
          <.input field={@smtp_form[:relay]} type="text" label="SMTP Relay" placeholder="smtp.example.com" />
          <.input field={@smtp_form[:port]} type="number" label="Port" />
          <.input field={@smtp_form[:username]} type="text" label="Username" />
          <.input field={@smtp_form[:password]} type="password" label="Password" value="" />
          <.input field={@smtp_form[:from_email]} type="email" label="From Email" />
          <.input field={@smtp_form[:from_name]} type="text" label="From Name" />
          <div class="flex items-center gap-4">
            <.input field={@smtp_form[:tls]} type="checkbox" label="Enable TLS" />
          </div>
          <:actions>
            <.button phx-disable-with="Saving...">Save SMTP Settings</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate_email", params, socket) do
    %{"current_password" => _password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &"#{SwitchTelemetryWeb.Endpoint.url()}/users/settings/confirm_email/#{&1}"
        )

        info = "A link to confirm your email change has been sent to the new address."

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> assign(email_form: to_form(Accounts.change_user_email(user)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => _password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated successfully.")
         |> redirect(to: ~p"/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("validate_smtp", %{"smtp_setting" => smtp_params}, socket) do
    changeset =
      socket.assigns.smtp_settings
      |> Settings.change_smtp_settings(smtp_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, smtp_form: to_form(changeset))}
  end

  def handle_event("update_smtp", %{"smtp_setting" => smtp_params}, socket) do
    case Settings.update_smtp_settings(smtp_params) do
      {:ok, smtp_settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "SMTP settings updated successfully.")
         |> assign(:smtp_settings, smtp_settings)
         |> assign(:smtp_form, to_form(Settings.change_smtp_settings(smtp_settings)))}

      {:error, changeset} ->
        {:noreply, assign(socket, smtp_form: to_form(changeset))}
    end
  end
end

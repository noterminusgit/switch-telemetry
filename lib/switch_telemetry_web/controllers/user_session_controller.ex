defmodule SwitchTelemetryWeb.UserSessionController do
  @moduledoc """
  Controller for user session management (login/logout).

  Handles creating and destroying user sessions.
  """

  use SwitchTelemetryWeb, :controller

  require Logger
  import Phoenix.Component, only: [to_form: 2]

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetryWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil, form: to_form(%{}, as: "user"))
  end

  def create(conn, %{"user" => user_params}) do
    Logger.warning("[LOGIN] Matched nested 'user' params")
    do_create(conn, user_params)
  end

  def create(conn, %{"email" => _, "password" => _} = params) do
    Logger.warning("[LOGIN] Matched flat params")
    do_create(conn, params)
  end

  defp do_create(conn, user_params) do
    %{"email" => email, "password" => password} = user_params

    Logger.warning("[LOGIN] email=#{inspect(email)} password_len=#{byte_size(password)} password_chars=#{inspect(:binary.bin_to_list(password))}")

    if user = Accounts.get_user_by_email_and_password(email, password) do
      Logger.warning("[LOGIN] Auth SUCCESS for #{email}")
      user = Accounts.maybe_promote_to_admin(user)

      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      Logger.warning("[LOGIN] Auth FAILED for #{email}")
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      render(conn, :new,
        error_message: "Invalid email or password",
        form: to_form(%{}, as: "user")
      )
    end
  end

  def create_magic_link(conn, %{"magic_link" => %{"email" => email}}) do
    if Accounts.admin_email?(email) do
      {:ok, user} = Accounts.get_or_create_user_for_magic_link(email)

      Accounts.deliver_magic_link_instructions(user, fn token ->
        url(conn, ~p"/users/magic_link/#{token}")
      end)
    end

    # Always show the same message to prevent enumeration
    conn
    |> put_flash(
      :info,
      "If your email is on the admin allowlist, you will receive a sign-in link shortly."
    )
    |> redirect(to: ~p"/users/log_in")
  end

  def magic_link_callback(conn, %{"token" => token}) do
    case Accounts.verify_magic_link_token(token) do
      {:ok, user} ->
        user = Accounts.maybe_promote_to_admin(user)

        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user)

      :error ->
        conn
        |> put_flash(:error, "Magic link is invalid or has expired.")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end

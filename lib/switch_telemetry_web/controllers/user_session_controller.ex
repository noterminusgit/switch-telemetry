defmodule SwitchTelemetryWeb.UserSessionController do
  @moduledoc """
  Controller for user session management (login/logout).

  Handles creating and destroying user sessions.
  """

  use SwitchTelemetryWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetryWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil, form: to_form(%{}, as: "user"))
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      render(conn, :new,
        error_message: "Invalid email or password",
        form: to_form(%{}, as: "user")
      )
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end

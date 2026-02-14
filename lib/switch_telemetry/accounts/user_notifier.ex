defmodule SwitchTelemetry.Accounts.UserNotifier do
  import Swoosh.Email

  alias SwitchTelemetry.Mailer

  # Generic deliver function
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Switch Telemetry", "noreply@switch-telemetry.local"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """
    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account, please ignore this.
    """)
  end

  @doc """
  Deliver a magic link for passwordless login.
  """
  def deliver_magic_link(user, url) do
    deliver(user.email, "Sign in to Switch Telemetry", """
    Hi #{user.email},

    You can sign in to Switch Telemetry by visiting the URL below:

    #{url}

    This link is valid for 24 hours and can only be used once.

    If you didn't request this, please ignore this email.
    """)
  end

  @doc """
  Deliver a generated password to a new user account.
  """
  def deliver_generated_password(user, password) do
    deliver(user.email, "Your Switch Telemetry account", """
    Hi #{user.email},

    An admin account has been created for you on Switch Telemetry.

    Your temporary password is:

      #{password}

    Please log in and change your password at your earliest convenience.
    """)
  end
end

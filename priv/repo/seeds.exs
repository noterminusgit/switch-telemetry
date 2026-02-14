# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     SwitchTelemetry.Repo.insert!(%SwitchTelemetry.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias SwitchTelemetry.Accounts
alias SwitchTelemetry.Accounts.User

admin_email = "admin@switch-telemetry.local"
admin_password = "Admin123!secure"

# Seed permanent admin account (idempotent)
unless Accounts.get_user_by_email(admin_email) do
  {:ok, user} =
    Accounts.register_user(%{
      email: admin_email,
      password: admin_password,
      role: :admin
    })

  # Auto-confirm the admin account
  user
  |> User.confirm_changeset()
  |> SwitchTelemetry.Repo.update!()

  IO.puts("Seeded admin account: #{admin_email}")
end

# Seed admin email allowlist entry (idempotent)
unless Accounts.admin_email?(admin_email) do
  {:ok, _} = Accounts.create_admin_email(%{email: admin_email})
  IO.puts("Added #{admin_email} to admin email allowlist")
end

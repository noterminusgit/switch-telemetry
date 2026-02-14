defmodule SwitchTelemetry.Repo.Migrations.CreateAdminEmails do
  use Ecto.Migration

  def change do
    create table(:admin_emails) do
      add :email, :citext, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:admin_emails, [:email])
  end
end

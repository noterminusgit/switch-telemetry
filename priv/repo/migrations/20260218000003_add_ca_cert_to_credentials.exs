defmodule SwitchTelemetry.Repo.Migrations.AddCaCertToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :ca_cert, :binary
    end
  end
end

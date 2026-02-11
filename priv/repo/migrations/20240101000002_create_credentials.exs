defmodule SwitchTelemetry.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :username, :string, null: false
      add :password, :text
      add :ssh_key, :text
      add :tls_cert, :text
      add :tls_key, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:credentials, [:name])
  end
end

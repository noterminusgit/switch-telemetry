defmodule SwitchTelemetry.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :string, primary_key: true
      add :device_id, references(:devices, type: :string), null: false
      add :paths, {:array, :string}, null: false
      add :mode, :string, default: "stream"
      add :sample_interval_ns, :bigint, default: 30_000_000_000
      add :encoding, :string, default: "proto"
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:subscriptions, [:device_id])
  end
end

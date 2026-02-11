defmodule SwitchTelemetry.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :string, primary_key: true
      add :hostname, :string, null: false
      add :ip_address, :string, null: false
      add :platform, :string, null: false
      add :transport, :string, null: false, default: "gnmi"
      add :gnmi_port, :integer, default: 57400
      add :netconf_port, :integer, default: 830
      add :credential_id, references(:credentials, type: :string)
      add :tags, :map, default: %{}
      add :collection_interval_ms, :integer, default: 30_000
      add :status, :string, default: "active"
      add :assigned_collector, :string
      add :collector_heartbeat, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:devices, [:hostname])
    create unique_index(:devices, [:ip_address])
    create index(:devices, [:status])
    create index(:devices, [:assigned_collector])
    create index(:devices, [:platform])
  end
end

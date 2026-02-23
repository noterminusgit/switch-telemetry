defmodule SwitchTelemetry.Repo.Migrations.AddGnmiEncodingToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :gnmi_encoding, :string, default: "proto"
    end
  end
end

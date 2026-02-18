defmodule SwitchTelemetry.Repo.Migrations.AddModelToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :model, :string
    end
  end
end

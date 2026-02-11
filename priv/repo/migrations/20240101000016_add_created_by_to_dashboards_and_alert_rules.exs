defmodule SwitchTelemetry.Repo.Migrations.AddCreatedByToDashboardsAndAlertRules do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :created_by, references(:users, type: :string, on_delete: :nilify_all)
    end

    alter table(:alert_rules) do
      add :created_by, references(:users, type: :string, on_delete: :nilify_all)
    end

    create index(:dashboards, [:created_by])
    create index(:alert_rules, [:created_by])
  end
end

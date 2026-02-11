defmodule SwitchTelemetry.Repo.Migrations.AddRetentionPolicies do
  use Ecto.Migration

  def up do
    execute "SELECT add_retention_policy('metrics', INTERVAL '30 days')"
    execute "SELECT add_retention_policy('metrics_5m', INTERVAL '180 days')"
    execute "SELECT add_retention_policy('metrics_1h', INTERVAL '730 days')"
  end

  def down do
    execute "SELECT remove_retention_policy('metrics')"
    execute "SELECT remove_retention_policy('metrics_5m')"
    execute "SELECT remove_retention_policy('metrics_1h')"
  end
end

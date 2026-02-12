defmodule SwitchTelemetry.Repo.Migrations.AddRetentionPolicies do
  use Ecto.Migration

  def up do
    execute "SELECT add_retention_policy('metrics', INTERVAL '30 days')"

    if timescaledb_community?() do
      execute "SELECT add_retention_policy('metrics_5m', INTERVAL '180 days')"
      execute "SELECT add_retention_policy('metrics_1h', INTERVAL '730 days')"
    end
  end

  def down do
    execute "SELECT remove_retention_policy('metrics')"

    if timescaledb_community?() do
      execute "SELECT remove_retention_policy('metrics_5m')"
      execute "SELECT remove_retention_policy('metrics_1h')"
    end
  end

  defp timescaledb_community? do
    %{rows: [[license]]} =
      repo().query!("SHOW timescaledb.license")

    license == "timescale"
  end
end

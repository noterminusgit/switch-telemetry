defmodule SwitchTelemetry.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    node_role = System.get_env("NODE_ROLE", "both")

    children =
      common_children() ++
        collector_children(node_role) ++
        web_children(node_role)

    opts = [strategy: :one_for_one, name: SwitchTelemetry.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SwitchTelemetryWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Always started on every node type
  defp common_children do
    [
      SwitchTelemetry.Repo,
      SwitchTelemetry.InfluxDB,
      SwitchTelemetry.Vault,
      {Phoenix.PubSub, name: SwitchTelemetry.PubSub},
      {Horde.Registry, name: SwitchTelemetry.DistributedRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: SwitchTelemetry.DistributedSupervisor, strategy: :one_for_one, members: :auto},
      {Finch, name: SwitchTelemetry.Finch}
    ]
  end

  # Only on collector nodes
  defp collector_children(role) when role in ["collector", "both"] do
    [
      SwitchTelemetry.Collector.DeviceAssignment,
      SwitchTelemetry.Collector.NodeMonitor,
      SwitchTelemetry.Collector.DeviceManager,
      SwitchTelemetry.Collector.StreamMonitor,
      {Oban, Application.fetch_env!(:switch_telemetry, Oban)}
    ]
  end

  defp collector_children(_), do: []

  # Only on web nodes
  defp web_children(role) when role in ["web", "both"] do
    [
      SwitchTelemetryWeb.Telemetry,
      SwitchTelemetryWeb.Endpoint
    ]
  end

  defp web_children(_), do: []
end

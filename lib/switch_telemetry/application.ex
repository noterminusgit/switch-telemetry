defmodule SwitchTelemetry.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    setup_file_logger()

    node_role = System.get_env("NODE_ROLE", "both")

    children =
      common_children() ++
        collector_children(node_role) ++
        web_children(node_role)

    opts = [strategy: :one_for_one, name: SwitchTelemetry.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_file_logger do
    log_dir = Path.join(Application.app_dir(:switch_telemetry, "../../"), "logs")
    File.mkdir_p!(log_dir)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d_%H-%M-%S")
    log_file = Path.join(log_dir, "switch_telemetry_#{timestamp}.log")

    :logger.add_handler(:file_log, :logger_std_h, %{
      config: %{
        file: String.to_charlist(log_file),
        max_no_bytes: 10_485_760,
        max_no_files: 100
      },
      formatter:
        {:logger_formatter,
         %{
           template: [:time, " ", :level, " ", :msg, "\n"],
           single_line: true
         }}
    })
  end

  @impl true
  def config_change(changed, _new, removed) do
    SwitchTelemetryWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Always started on every node type
  @doc false
  def common_children do
    [
      SwitchTelemetry.Repo,
      SwitchTelemetry.InfluxDB,
      SwitchTelemetry.Vault,
      {Phoenix.PubSub, name: SwitchTelemetry.PubSub},
      {Horde.Registry, name: SwitchTelemetry.DistributedRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: SwitchTelemetry.DistributedSupervisor, strategy: :one_for_one, members: :auto},
      {Finch, name: SwitchTelemetry.Finch},
      {GRPC.Client.Supervisor, []}
    ]
  end

  # Only on collector nodes
  @doc false
  def collector_children(role) when role in ["collector", "both"] do
    [
      SwitchTelemetry.Collector.DeviceAssignment,
      SwitchTelemetry.Collector.NodeMonitor,
      SwitchTelemetry.Collector.DeviceManager,
      SwitchTelemetry.Collector.StreamMonitor,
      {Oban, Application.fetch_env!(:switch_telemetry, Oban)}
    ]
  end

  def collector_children(_), do: []

  # Only on web nodes
  @doc false
  def web_children(role) when role in ["web", "both"] do
    [
      SwitchTelemetryWeb.Telemetry,
      SwitchTelemetryWeb.Endpoint
    ]
  end

  def web_children(_), do: []
end

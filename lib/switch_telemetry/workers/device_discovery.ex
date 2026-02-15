defmodule SwitchTelemetry.Workers.DeviceDiscovery do
  @moduledoc """
  Oban worker that periodically checks for new or changed devices
  and triggers session management accordingly.

  Runs on the discovery queue. Ensures that newly added devices
  get assigned to collectors and have their sessions started.
  """
  use Oban.Worker, queue: :discovery, max_attempts: 3

  require Logger

  alias SwitchTelemetry.Devices

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    Logger.info("Running device discovery")

    # Find active devices without a collector assignment
    unassigned =
      Devices.list_devices_by_status(:active)
      |> Enum.filter(fn d -> is_nil(d.assigned_collector) or d.assigned_collector == "" end)

    if unassigned != [] do
      Logger.info("Found #{length(unassigned)} unassigned devices")

      Enum.each(unassigned, fn device ->
        assign_device(device)
      end)
    end

    # Check for stale device heartbeats (collector may have died without clean shutdown)
    check_stale_heartbeats()

    :ok
  end

  defp assign_device(device) do
    if Code.ensure_loaded?(SwitchTelemetry.Collector.DeviceAssignment) and
         Process.whereis(SwitchTelemetry.Collector.DeviceAssignment) do
      case SwitchTelemetry.Collector.DeviceAssignment.get_owner(device.id) do
        {:ok, node} ->
          collector = Atom.to_string(node)
          Devices.update_device(device, %{assigned_collector: collector})
          Logger.info("Assigned #{device.hostname} to #{collector}")

        _ ->
          Logger.warning("No collectors available to assign #{device.hostname}")
      end
    end
  end

  defp check_stale_heartbeats do
    stale_threshold = DateTime.add(DateTime.utc_now(), -60, :second)

    Devices.list_devices_by_status(:active)
    |> Enum.filter(fn d ->
      d.collector_heartbeat != nil and
        DateTime.compare(d.collector_heartbeat, stale_threshold) == :lt
    end)
    |> Enum.each(fn device ->
      Logger.warning(
        "Stale heartbeat for #{device.hostname} (last: #{device.collector_heartbeat})"
      )

      Devices.update_device(device, %{status: :unreachable})
    end)
  end
end

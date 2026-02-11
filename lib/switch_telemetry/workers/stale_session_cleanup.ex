defmodule SwitchTelemetry.Workers.StaleSessionCleanup do
  @moduledoc """
  Oban worker that cleans up stale device sessions.

  Detects sessions that are registered in Horde but whose owning
  collector node is no longer in the cluster, and removes them
  so they can be restarted on healthy nodes.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running stale session cleanup")

    active_nodes = MapSet.new([Node.self() | Node.list()])

    # Check all registered sessions in Horde
    registered =
      Horde.Registry.select(SwitchTelemetry.DistributedRegistry, [
        {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
      ])

    stale_count =
      Enum.count(registered, fn {_key, pid} ->
        node = node(pid)

        unless MapSet.member?(active_nodes, node) do
          Logger.warning("Cleaning up stale session on dead node #{node}: #{inspect(pid)}")

          try do
            Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, pid)
          catch
            _, _ -> :ok
          end

          true
        end
      end)

    if stale_count > 0 do
      Logger.info("Cleaned up #{stale_count} stale sessions")

      # Trigger rebalance to reassign orphaned devices
      if Process.whereis(SwitchTelemetry.Collector.DeviceAssignment) do
        SwitchTelemetry.Collector.DeviceAssignment.rebalance()
      end
    end

    :ok
  end
end

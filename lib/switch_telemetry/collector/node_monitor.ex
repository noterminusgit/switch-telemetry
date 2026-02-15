defmodule SwitchTelemetry.Collector.NodeMonitor do
  @moduledoc """
  Monitors cluster membership changes and triggers failover handling.

  When a collector node goes down, NodeMonitor detects it via
  :net_kernel.monitor_nodes/2 and notifies DeviceAssignment to
  rebalance device ownership. DeviceManager then picks up newly
  assigned devices on the next check cycle.
  """
  use GenServer
  require Logger

  @heartbeat_interval :timer.seconds(15)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec cluster_status() :: %{self: node(), nodes: [node()], node_count: non_neg_integer()}
  def cluster_status do
    GenServer.call(__MODULE__, :cluster_status)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    schedule_heartbeat()
    {:ok, %{nodes: MapSet.new([Node.self() | Node.list()])}}
  end

  @impl true
  def handle_call(:cluster_status, _from, state) do
    status = %{
      self: Node.self(),
      nodes: MapSet.to_list(state.nodes),
      node_count: MapSet.size(state.nodes)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("Cluster: node UP #{node}")
    nodes = MapSet.put(state.nodes, node)

    :telemetry.execute(
      [:switch_telemetry, :cluster, :node_up],
      %{count: 1},
      %{node: node}
    )

    {:noreply, %{state | nodes: nodes}}
  end

  def handle_info({:nodedown, node, _info}, state) do
    Logger.warning("Cluster: node DOWN #{node}")
    nodes = MapSet.delete(state.nodes, node)

    :telemetry.execute(
      [:switch_telemetry, :cluster, :node_down],
      %{count: 1},
      %{node: node}
    )

    # Trigger rebalance after a brief delay to let Horde settle
    Process.send_after(self(), :trigger_rebalance, 2_000)

    {:noreply, %{state | nodes: nodes}}
  end

  def handle_info(:trigger_rebalance, state) do
    if Process.whereis(SwitchTelemetry.Collector.DeviceAssignment) do
      SwitchTelemetry.Collector.DeviceAssignment.rebalance()
    end

    {:noreply, state}
  end

  def handle_info(:heartbeat, state) do
    update_collector_heartbeat()

    :telemetry.execute(
      [:switch_telemetry, :cluster, :nodes],
      %{count: MapSet.size(state.nodes)}
    )

    schedule_heartbeat()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp update_collector_heartbeat do
    import Ecto.Query

    collector_node = Atom.to_string(Node.self())
    now = DateTime.utc_now()

    from(d in SwitchTelemetry.Devices.Device,
      where: d.assigned_collector == ^collector_node
    )
    |> SwitchTelemetry.Repo.update_all(set: [collector_heartbeat: now])
  rescue
    DBConnection.OwnershipError -> :ok
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end
end

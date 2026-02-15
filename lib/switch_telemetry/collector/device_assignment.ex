defmodule SwitchTelemetry.Collector.DeviceAssignment do
  @moduledoc """
  Assigns devices to collector nodes using consistent hashing.

  When a collector node joins or leaves the cluster, the hash ring is
  rebuilt and only ~1/N devices need to be reassigned. Uses the
  hash_ring library for consistent hashing.

  Monitors BEAM node membership via :net_kernel.monitor_nodes/2.
  """
  use GenServer
  require Logger

  alias SwitchTelemetry.{Devices, Repo}
  alias SwitchTelemetry.Devices.Device

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the collector node that should own the given device.
  """
  @spec get_owner(String.t()) :: {:ok, node()} | {:error, :no_collectors}
  def get_owner(device_id) do
    GenServer.call(__MODULE__, {:get_owner, device_id})
  end

  @doc """
  Forces a reassignment of all devices based on the current hash ring.
  """
  @spec rebalance() :: :ok
  def rebalance do
    GenServer.cast(__MODULE__, :rebalance)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    ring = rebuild_ring()
    send(self(), :initial_assignment)
    {:ok, %{ring: ring}}
  end

  @impl true
  def handle_call({:get_owner, device_id}, _from, state) do
    case HashRing.key_to_node(state.ring, device_id) do
      node when is_atom(node) -> {:reply, {:ok, node}, state}
      _ -> {:reply, {:error, :no_collectors}, state}
    end
  end

  @impl true
  def handle_cast(:rebalance, state) do
    do_rebalance(state.ring)
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("Node joined cluster: #{node}")
    ring = rebuild_ring()
    do_rebalance(ring)
    {:noreply, %{state | ring: ring}}
  end

  def handle_info({:nodedown, node, _info}, state) do
    Logger.warning("Node left cluster: #{node}")
    ring = rebuild_ring()
    do_rebalance(ring)
    {:noreply, %{state | ring: ring}}
  end

  def handle_info(:initial_assignment, state) do
    do_rebalance(state.ring)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp rebuild_ring do
    [Node.self() | Node.list()]
    |> Enum.filter(&collector_node?/1)
    |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))
  end

  defp collector_node?(node) do
    node_str = Atom.to_string(node)
    String.starts_with?(node_str, "collector") or node_str == Atom.to_string(Node.self())
  end

  defp do_rebalance(ring) do
    import Ecto.Query

    devices =
      from(d in Device, where: d.status in [:active, :unreachable], select: d)
      |> Repo.all()

    Enum.each(devices, fn device ->
      case HashRing.key_to_node(ring, device.id) do
        node when is_atom(node) ->
          new_collector = Atom.to_string(node)

          if device.assigned_collector != new_collector do
            Devices.update_device(device, %{assigned_collector: new_collector})

            Logger.info(
              "Reassigned #{device.hostname} from #{device.assigned_collector} to #{new_collector}"
            )
          end

        _ ->
          :ok
      end
    end)
  rescue
    e ->
      Logger.error("Rebalance failed: #{inspect(e)}")
  end
end

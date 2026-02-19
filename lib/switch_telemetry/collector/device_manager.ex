defmodule SwitchTelemetry.Collector.DeviceManager do
  @moduledoc """
  Manages device telemetry sessions on this collector node.

  On startup, loads all devices assigned to this node and starts
  GnmiSession/NetconfSession processes via Horde.DynamicSupervisor.
  Handles start/stop of individual device sessions and responds to
  assignment changes from DeviceAssignment.
  """
  use GenServer
  require Logger

  alias SwitchTelemetry.Devices
  alias SwitchTelemetry.Collector.{GnmiSession, NetconfSession}

  @check_interval :timer.seconds(30)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_device_session(String.t()) :: :ok | {:error, term()}
  def start_device_session(device_id) do
    GenServer.call(__MODULE__, {:start_session, device_id})
  end

  @spec stop_device_session(String.t()) :: :ok
  def stop_device_session(device_id) do
    GenServer.call(__MODULE__, {:stop_session, device_id})
  end

  @spec list_sessions() :: [String.t()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    send(self(), :start_assigned_devices)
    schedule_check()
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:start_session, device_id}, _from, state) do
    case do_start_session(device_id) do
      {:ok, pids} ->
        sessions = Map.put(state.sessions, device_id, pids)
        {:reply, :ok, %{state | sessions: sessions}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stop_session, device_id}, _from, state) do
    do_stop_session(device_id, state.sessions)
    sessions = Map.delete(state.sessions, device_id)
    {:reply, :ok, %{state | sessions: sessions}}
  end

  def handle_call(:list_sessions, _from, state) do
    {:reply, Map.keys(state.sessions), state}
  end

  @impl true
  def handle_info(:start_assigned_devices, state) do
    collector_node = Atom.to_string(Node.self())

    devices = Devices.list_devices_for_collector(collector_node)

    sessions =
      Enum.reduce(devices, state.sessions, fn device, acc ->
        case do_start_session(device.id) do
          {:ok, pids} ->
            Map.put(acc, device.id, pids)

          {:error, reason} ->
            Logger.warning("Failed to start session for #{device.hostname}: #{inspect(reason)}")

            acc
        end
      end)

    Logger.info("DeviceManager started #{map_size(sessions)} device sessions")
    {:noreply, %{state | sessions: sessions}}
  rescue
    e ->
      Logger.warning("DeviceManager start_assigned_devices failed: #{inspect(e)}")
      {:noreply, state}
  end

  def handle_info(:check_sessions, state) do
    # Reconcile sessions with current assignments
    collector_node = Atom.to_string(Node.self())
    assigned_devices = Devices.list_devices_for_collector(collector_node)
    assigned_ids = MapSet.new(Enum.map(assigned_devices, & &1.id))
    running_ids = MapSet.new(Map.keys(state.sessions))

    # Start sessions for newly assigned devices
    to_start = MapSet.difference(assigned_ids, running_ids)

    sessions =
      Enum.reduce(to_start, state.sessions, fn device_id, acc ->
        case do_start_session(device_id) do
          {:ok, pids} -> Map.put(acc, device_id, pids)
          {:error, _} -> acc
        end
      end)

    # Stop sessions for unassigned devices
    to_stop = MapSet.difference(running_ids, assigned_ids)

    sessions =
      Enum.reduce(to_stop, sessions, fn device_id, acc ->
        do_stop_session(device_id, acc)
        Map.delete(acc, device_id)
      end)

    schedule_check()
    {:noreply, %{state | sessions: sessions}}
  rescue
    e ->
      Logger.warning("DeviceManager check_sessions failed: #{inspect(e)}")
      schedule_check()
      {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp do_start_session(device_id) do
    device = Devices.get_device!(device_id)
    pids = %{}

    pids =
      if device.transport in [:gnmi, :both] do
        case start_child(GnmiSession, device) do
          {:ok, pid} -> Map.put(pids, :gnmi, pid)
          {:error, {:already_started, pid}} -> Map.put(pids, :gnmi, pid)
          _ -> pids
        end
      else
        pids
      end

    pids =
      if device.transport in [:netconf, :both] do
        case start_child(NetconfSession, device) do
          {:ok, pid} -> Map.put(pids, :netconf, pid)
          {:error, {:already_started, pid}} -> Map.put(pids, :netconf, pid)
          _ -> pids
        end
      else
        pids
      end

    if map_size(pids) > 0 do
      Logger.info("Started sessions for #{device.hostname}: #{inspect(Map.keys(pids))}")
      {:ok, pids}
    else
      {:error, :no_sessions_started}
    end
  rescue
    e -> {:error, e}
  end

  defp start_child(module, device) do
    Horde.DynamicSupervisor.start_child(
      SwitchTelemetry.DistributedSupervisor,
      {module, device: device}
    )
  end

  defp do_stop_session(device_id, sessions) do
    case Map.get(sessions, device_id) do
      nil ->
        :ok

      pids ->
        Enum.each(pids, fn {type, pid} ->
          Logger.info("Stopping #{type} session for device #{device_id}")

          try do
            GenServer.stop(pid, :normal, 5_000)
          catch
            :exit, _ -> :ok
          end
        end)
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check_sessions, @check_interval)
  end
end

defmodule SwitchTelemetry.Collector.StreamMonitor do
  @moduledoc """
  Monitors the status of all active telemetry streams (gNMI and NETCONF sessions).

  Tracks:
  - Connection state (connected, disconnected, reconnecting)
  - Last message received timestamp
  - Message rate (messages per second)
  - Error counts

  Broadcasts status updates via PubSub for real-time UI updates.
  """
  use GenServer
  require Logger

  alias SwitchTelemetry.Devices

  @cleanup_interval :timer.minutes(5)
  @stale_threshold :timer.minutes(2)
  @pubsub SwitchTelemetry.PubSub
  @topic "stream_monitor"

  defstruct streams: %{}

  # Stream status structure
  defmodule StreamStatus do
    @type t :: %__MODULE__{}

    defstruct [
      :device_id,
      :device_hostname,
      :protocol,
      :state,
      :connected_at,
      :last_message_at,
      :message_count,
      :error_count,
      :last_error
    ]
  end

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec report_connected(String.t(), atom()) :: :ok
  def report_connected(device_id, protocol) do
    GenServer.cast(__MODULE__, {:connected, device_id, protocol})
  end

  @spec report_disconnected(String.t(), atom(), term()) :: :ok
  def report_disconnected(device_id, protocol, reason \\ nil) do
    GenServer.cast(__MODULE__, {:disconnected, device_id, protocol, reason})
  end

  @spec report_message(String.t(), atom()) :: :ok
  def report_message(device_id, protocol) do
    GenServer.cast(__MODULE__, {:message, device_id, protocol})
  end

  @spec report_error(String.t(), atom(), term()) :: :ok
  def report_error(device_id, protocol, error) do
    GenServer.cast(__MODULE__, {:error, device_id, protocol, error})
  end

  @spec list_streams() :: [StreamStatus.t()]
  def list_streams do
    GenServer.call(__MODULE__, :list_streams)
  end

  @spec get_stream(String.t(), atom()) :: StreamStatus.t() | nil
  def get_stream(device_id, protocol) do
    GenServer.call(__MODULE__, {:get_stream, device_id, protocol})
  end

  @spec subscribe() :: :ok | {:error, {:already_registered, pid()}}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:connected, device_id, protocol}, state) do
    device = safe_get_device(device_id)

    status = %StreamStatus{
      device_id: device_id,
      device_hostname: device && device.hostname,
      protocol: protocol,
      state: :connected,
      connected_at: DateTime.utc_now(),
      last_message_at: nil,
      message_count: 0,
      error_count: 0,
      last_error: nil
    }

    key = {device_id, protocol}
    streams = Map.put(state.streams, key, status)
    broadcast_update(status)
    {:noreply, %{state | streams: streams}}
  end

  def handle_cast({:disconnected, device_id, protocol, reason}, state) do
    key = {device_id, protocol}

    streams =
      Map.update(state.streams, key, nil, fn status ->
        if status do
          updated = %{status | state: :disconnected, last_error: format_error(reason)}
          broadcast_update(updated)
          updated
        else
          nil
        end
      end)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, %{state | streams: streams}}
  end

  def handle_cast({:message, device_id, protocol}, state) do
    key = {device_id, protocol}

    streams =
      Map.update(state.streams, key, nil, fn status ->
        if status do
          updated = %{
            status
            | last_message_at: DateTime.utc_now(),
              message_count: status.message_count + 1
          }

          updated
        else
          nil
        end
      end)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, %{state | streams: streams}}
  end

  def handle_cast({:error, device_id, protocol, error}, state) do
    key = {device_id, protocol}

    streams =
      Map.update(state.streams, key, nil, fn status ->
        if status do
          updated = %{
            status
            | error_count: status.error_count + 1,
              last_error: format_error(error)
          }

          broadcast_update(updated)
          updated
        else
          nil
        end
      end)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    {:noreply, %{state | streams: streams}}
  end

  @impl true
  def handle_call(:list_streams, _from, state) do
    streams = Map.values(state.streams) |> Enum.sort_by(& &1.device_hostname)
    {:reply, streams, state}
  end

  def handle_call({:get_stream, device_id, protocol}, _from, state) do
    key = {device_id, protocol}
    {:reply, Map.get(state.streams, key), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()
    stale_threshold_ms = @stale_threshold

    streams =
      state.streams
      |> Enum.filter(fn {_key, status} ->
        case status.last_message_at do
          nil ->
            DateTime.diff(now, status.connected_at, :millisecond) < stale_threshold_ms

          last ->
            DateTime.diff(now, last, :millisecond) < stale_threshold_ms
        end
      end)
      |> Map.new()

    removed_count = map_size(state.streams) - map_size(streams)

    if removed_count > 0 do
      Logger.debug("StreamMonitor cleaned up #{removed_count} stale stream entries")
      broadcast_full_update(streams)
    end

    schedule_cleanup()
    {:noreply, %{state | streams: streams}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp safe_get_device(device_id) do
    Devices.get_device(device_id)
  rescue
    _ -> nil
  end

  defp format_error(nil), do: nil
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp broadcast_update(status) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:stream_update, status})
  end

  defp broadcast_full_update(streams) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:streams_full, Map.values(streams)})
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end

defmodule SwitchTelemetry.Collector.StreamMonitorTest do
  use SwitchTelemetry.DataCase, async: false

  alias SwitchTelemetry.Collector.StreamMonitor
  alias SwitchTelemetry.Devices

  defp valid_device_attrs(overrides \\ %{}) do
    n = System.unique_integer([:positive])
    id = "dev-#{n}"

    Map.merge(
      %{
        id: id,
        hostname: "switch-#{n}",
        ip_address: "10.0.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
        platform: :cisco_iosxr,
        transport: :gnmi
      },
      overrides
    )
  end

  defp create_device do
    {:ok, device} = Devices.create_device(valid_device_attrs())
    device
  end

  setup do
    # Reset the already-running StreamMonitor to a clean state
    :sys.replace_state(StreamMonitor, fn _state -> %StreamMonitor{} end)
    :ok
  end

  describe "report_connected/2" do
    test "adds stream to tracking" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)

      # Give a moment for the async cast to process
      Process.sleep(10)

      streams = StreamMonitor.list_streams()
      assert length(streams) == 1
      [stream] = streams
      assert stream.device_id == device.id
      assert stream.protocol == :gnmi
      assert stream.state == :connected
      assert stream.message_count == 0
      assert stream.error_count == 0
    end

    test "tracks multiple protocols for same device" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      StreamMonitor.report_connected(device.id, :netconf)

      Process.sleep(10)

      streams = StreamMonitor.list_streams()
      assert length(streams) == 2
      protocols = Enum.map(streams, & &1.protocol) |> Enum.sort()
      assert protocols == [:gnmi, :netconf]
    end

    test "tracks device hostname" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)

      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.device_hostname == device.hostname
    end
  end

  describe "report_disconnected/3" do
    test "updates stream state to disconnected" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      StreamMonitor.report_disconnected(device.id, :gnmi, "connection reset")
      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.state == :disconnected
      assert stream.last_error == "connection reset"
    end

    test "handles disconnect for non-existent stream" do
      device = create_device()
      # Should not raise
      StreamMonitor.report_disconnected(device.id, :gnmi, nil)
      Process.sleep(10)
      assert StreamMonitor.list_streams() == []
    end
  end

  describe "report_message/2" do
    test "increments message count" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      StreamMonitor.report_message(device.id, :gnmi)
      StreamMonitor.report_message(device.id, :gnmi)
      StreamMonitor.report_message(device.id, :gnmi)
      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.message_count == 3
    end

    test "updates last_message_at timestamp" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      [stream_before] = StreamMonitor.list_streams()
      assert stream_before.last_message_at == nil

      StreamMonitor.report_message(device.id, :gnmi)
      Process.sleep(10)

      [stream_after] = StreamMonitor.list_streams()
      assert stream_after.last_message_at != nil
    end
  end

  describe "report_error/3" do
    test "increments error count" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      StreamMonitor.report_error(device.id, :gnmi, "timeout")
      StreamMonitor.report_error(device.id, :gnmi, "parse error")
      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.error_count == 2
    end

    test "updates last_error" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      StreamMonitor.report_error(device.id, :gnmi, "first error")
      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.last_error == "first error"

      StreamMonitor.report_error(device.id, :gnmi, "second error")
      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.last_error == "second error"
    end

    test "formats non-string errors" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      StreamMonitor.report_error(device.id, :gnmi, {:error, :timeout})
      Process.sleep(10)

      [stream] = StreamMonitor.list_streams()
      assert stream.last_error == "{:error, :timeout}"
    end
  end

  describe "list_streams/0" do
    test "returns sorted list by hostname" do
      device_a = create_device()
      device_b = create_device()

      # Ensure different hostnames for sorting test
      {:ok, device_a} = Devices.update_device(device_a, %{hostname: "aaa-switch"})
      {:ok, device_b} = Devices.update_device(device_b, %{hostname: "zzz-switch"})

      StreamMonitor.report_connected(device_b.id, :gnmi)
      StreamMonitor.report_connected(device_a.id, :gnmi)
      Process.sleep(10)

      streams = StreamMonitor.list_streams()
      hostnames = Enum.map(streams, & &1.device_hostname)
      assert hostnames == Enum.sort(hostnames)
    end
  end

  describe "get_stream/2" do
    test "returns specific stream" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      StreamMonitor.report_connected(device.id, :netconf)
      Process.sleep(10)

      gnmi_stream = StreamMonitor.get_stream(device.id, :gnmi)
      assert gnmi_stream.protocol == :gnmi

      netconf_stream = StreamMonitor.get_stream(device.id, :netconf)
      assert netconf_stream.protocol == :netconf
    end

    test "returns nil for non-existent stream" do
      assert StreamMonitor.get_stream("nonexistent", :gnmi) == nil
    end
  end

  describe "subscribe/0" do
    test "receives stream updates via PubSub" do
      StreamMonitor.subscribe()
      device = create_device()

      StreamMonitor.report_connected(device.id, :gnmi)

      assert_receive {:stream_update, status}, 1000
      assert status.device_id == device.id
      assert status.state == :connected
    end
  end

  describe "stale stream cleanup" do
    test "removes streams inactive for more than 2 minutes" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      # Verify the stream exists
      assert [_stream] = StreamMonitor.list_streams()

      # Manually set the stream's connected_at and last_message_at to an old time
      # to simulate a stale stream (more than 2 minutes old)
      old_time = DateTime.add(DateTime.utc_now(), -180, :second)

      :sys.replace_state(StreamMonitor, fn state ->
        key = {device.id, :gnmi}

        updated_streams =
          Map.update!(state.streams, key, fn status ->
            %{status | connected_at: old_time, last_message_at: nil}
          end)

        %{state | streams: updated_streams}
      end)

      # Trigger the cleanup timer manually
      send(Process.whereis(StreamMonitor), :cleanup)
      Process.sleep(50)

      # Stream should be removed because it's stale
      assert StreamMonitor.list_streams() == []
    end

    test "keeps streams that received a recent message" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      # Set connected_at to old time but last_message_at to recent
      old_time = DateTime.add(DateTime.utc_now(), -300, :second)

      :sys.replace_state(StreamMonitor, fn state ->
        key = {device.id, :gnmi}

        updated_streams =
          Map.update!(state.streams, key, fn status ->
            %{status | connected_at: old_time, last_message_at: DateTime.utc_now()}
          end)

        %{state | streams: updated_streams}
      end)

      # Trigger cleanup
      send(Process.whereis(StreamMonitor), :cleanup)
      Process.sleep(50)

      # Stream should still be present because last_message_at is recent
      assert [stream] = StreamMonitor.list_streams()
      assert stream.device_id == device.id
    end

    test "keeps recently connected streams with no messages" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      # Trigger cleanup -- the stream was just created, so it's not stale
      send(Process.whereis(StreamMonitor), :cleanup)
      Process.sleep(50)

      assert [stream] = StreamMonitor.list_streams()
      assert stream.device_id == device.id
    end

    test "removes multiple stale streams at once" do
      device1 = create_device()
      device2 = create_device()
      StreamMonitor.report_connected(device1.id, :gnmi)
      StreamMonitor.report_connected(device2.id, :netconf)
      Process.sleep(10)

      assert length(StreamMonitor.list_streams()) == 2

      # Make both stale
      old_time = DateTime.add(DateTime.utc_now(), -300, :second)

      :sys.replace_state(StreamMonitor, fn state ->
        updated_streams =
          state.streams
          |> Enum.map(fn {key, status} ->
            {key, %{status | connected_at: old_time, last_message_at: nil}}
          end)
          |> Map.new()

        %{state | streams: updated_streams}
      end)

      send(Process.whereis(StreamMonitor), :cleanup)
      Process.sleep(50)

      assert StreamMonitor.list_streams() == []
    end
  end

  describe "broadcast_full_update" do
    test "broadcasts full stream list after cleanup removes stale entries" do
      StreamMonitor.subscribe()

      device_fresh = create_device()
      device_stale = create_device()

      StreamMonitor.report_connected(device_fresh.id, :gnmi)
      StreamMonitor.report_connected(device_stale.id, :gnmi)

      # Drain the individual :stream_update messages from connect
      assert_receive {:stream_update, _}, 1000
      assert_receive {:stream_update, _}, 1000

      Process.sleep(10)

      # Make one stream stale
      old_time = DateTime.add(DateTime.utc_now(), -300, :second)

      :sys.replace_state(StreamMonitor, fn state ->
        key = {device_stale.id, :gnmi}

        updated_streams =
          Map.update!(state.streams, key, fn status ->
            %{status | connected_at: old_time, last_message_at: nil}
          end)

        %{state | streams: updated_streams}
      end)

      # Trigger cleanup -- should broadcast full update since entries were removed
      send(Process.whereis(StreamMonitor), :cleanup)

      assert_receive {:streams_full, streams}, 1000
      assert length(streams) == 1
      assert hd(streams).device_id == device_fresh.id
    end

    test "does not broadcast full update when no stale entries are removed" do
      StreamMonitor.subscribe()

      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)

      # Drain the :stream_update from connect
      assert_receive {:stream_update, _}, 1000

      Process.sleep(10)

      # Trigger cleanup -- nothing stale, so no full update broadcast
      send(Process.whereis(StreamMonitor), :cleanup)
      Process.sleep(50)

      refute_receive {:streams_full, _}
    end
  end

  describe "multiple errors" do
    test "increments error count for repeated errors" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      StreamMonitor.report_error(device.id, :gnmi, "timeout")
      StreamMonitor.report_error(device.id, :gnmi, "connection refused")
      Process.sleep(10)

      stream = StreamMonitor.get_stream(device.id, :gnmi)
      assert stream.error_count == 2
      assert stream.last_error == "connection refused"
    end

    test "error count accumulates across many errors" do
      device = create_device()
      StreamMonitor.report_connected(device.id, :gnmi)
      Process.sleep(10)

      for i <- 1..10 do
        StreamMonitor.report_error(device.id, :gnmi, "error #{i}")
      end

      Process.sleep(50)

      stream = StreamMonitor.get_stream(device.id, :gnmi)
      assert stream.error_count == 10
      assert stream.last_error == "error 10"
    end

    test "errors on non-existent stream do not create new entries" do
      StreamMonitor.report_error("nonexistent-device", :gnmi, "some error")
      Process.sleep(10)

      assert StreamMonitor.list_streams() == []
    end

    test "messages on non-existent stream do not create new entries" do
      StreamMonitor.report_message("nonexistent-device", :gnmi)
      Process.sleep(10)

      assert StreamMonitor.list_streams() == []
    end
  end

  describe "handle_info unknown messages" do
    test "ignores unknown messages without crashing" do
      # Send an unknown message to the StreamMonitor process
      send(Process.whereis(StreamMonitor), :some_unknown_message)
      Process.sleep(10)

      # Should still be alive and functional
      assert StreamMonitor.list_streams() == []
    end
  end
end

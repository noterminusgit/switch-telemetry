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
    # Start the StreamMonitor for testing
    start_supervised!(StreamMonitor)
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
end

defmodule SwitchTelemetry.Collector.GnmiSessionLifecycleTest do
  @moduledoc """
  Tests the GenServer lifecycle callbacks of GnmiSession by invoking
  handle_info/terminate directly with Mox-based mock expectations.
  """
  use SwitchTelemetry.DataCase, async: false

  import Mox

  alias SwitchTelemetry.Collector.GnmiSession
  alias SwitchTelemetry.Collector.MockGrpcClient
  alias SwitchTelemetry.{Collector, Devices}

  setup :verify_on_exit!

  setup do
    Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)
    on_exit(fn -> Application.delete_env(:switch_telemetry, :grpc_client) end)
    :ok
  end

  # -- Fixture helpers --

  defp unique_int, do: System.unique_integer([:positive])

  defp create_device(overrides \\ %{}) do
    n = unique_int()

    attrs =
      Map.merge(
        %{
          id: "dev-#{n}",
          hostname: "switch-#{n}",
          ip_address: "10.0.#{rem(n, 254) + 1}.#{rem(n, 253) + 1}",
          platform: :cisco_iosxr,
          transport: :gnmi,
          gnmi_port: 57400
        },
        overrides
      )

    {:ok, device} = Devices.create_device(attrs)
    device
  end

  defp create_subscription(device, paths \\ ["/interfaces/interface/state/counters"]) do
    n = unique_int()

    {:ok, sub} =
      Collector.create_subscription(%{
        id: "sub-#{n}",
        device_id: device.id,
        paths: paths
      })

    sub
  end

  defp make_state(device, overrides \\ []) do
    defaults = %GnmiSession{
      device: device,
      retry_count: 0,
      channel: nil,
      stream: nil,
      task_ref: nil
    }

    struct!(defaults, overrides)
  end

  # -- Tests --

  describe "init/1" do
    test "sets trap_exit, sends :connect, initializes state" do
      device = create_device()
      {:ok, state} = GnmiSession.init(device: device)

      assert state.device.id == device.id
      assert state.retry_count == 0
      assert state.channel == nil
      assert state.stream == nil
      assert state.task_ref == nil
      assert_received :connect
    end
  end

  describe "handle_info :connect" do
    test "success sets channel, resets retry_count, sends :subscribe" do
      device = create_device()
      state = make_state(device, retry_count: 3)

      MockGrpcClient
      |> expect(:connect, fn target, _opts ->
        assert target == "#{device.ip_address}:#{device.gnmi_port}"
        {:ok, :fake_channel}
      end)

      {:noreply, new_state} = GnmiSession.handle_info(:connect, state)

      assert new_state.channel == :fake_channel
      assert new_state.retry_count == 0
      assert_received :subscribe
    end

    test "success updates device status to active" do
      device = create_device(%{status: :unreachable})
      state = make_state(device)

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :fake_channel} end)

      {:noreply, _new_state} = GnmiSession.handle_info(:connect, state)

      updated_device = Devices.get_device!(device.id)
      assert updated_device.status == :active
      assert updated_device.last_seen_at != nil
    end

    test "failure increments retry_count and schedules retry" do
      device = create_device()
      state = make_state(device, retry_count: 0)

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:error, :connection_refused} end)

      {:noreply, new_state} = GnmiSession.handle_info(:connect, state)

      assert new_state.retry_count == 1
      assert new_state.channel == nil
      refute_received :subscribe
    end

    test "failure updates device status to unreachable" do
      device = create_device(%{status: :active})
      state = make_state(device)

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:error, :timeout} end)

      {:noreply, _new_state} = GnmiSession.handle_info(:connect, state)

      updated_device = Devices.get_device!(device.id)
      assert updated_device.status == :unreachable
    end

    test "repeated failures keep incrementing retry_count" do
      device = create_device()
      state = make_state(device, retry_count: 4)

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:error, :refused} end)

      {:noreply, new_state} = GnmiSession.handle_info(:connect, state)

      assert new_state.retry_count == 5
    end
  end

  describe "handle_info :subscribe" do
    test "creates stream, sends request, starts async task" do
      device = create_device()
      _sub = create_subscription(device)

      state = make_state(device, channel: :fake_channel)

      MockGrpcClient
      |> expect(:subscribe, fn :fake_channel -> :fake_stream end)
      |> expect(:send_request, fn :fake_stream, %Gnmi.SubscribeRequest{} -> :ok end)
      |> stub(:end_stream, fn :fake_stream -> :fake_stream end)
      |> expect(:recv, fn :fake_stream -> {:error, :test_exit} end)

      {:noreply, new_state} = GnmiSession.handle_info(:subscribe, state)

      assert new_state.stream == :fake_stream
      assert is_reference(new_state.task_ref)

      # Allow the task to complete so it doesn't leak
      Process.sleep(50)
    end

    test "builds subscriptions from database paths" do
      device = create_device()
      _sub1 = create_subscription(device, ["/interfaces/interface/state/counters"])
      _sub2 = create_subscription(device, ["/system/state/hostname"])

      state = make_state(device, channel: :fake_channel)

      MockGrpcClient
      |> expect(:subscribe, fn :fake_channel -> :fake_stream end)
      |> expect(:send_request, fn :fake_stream, %Gnmi.SubscribeRequest{} = req ->
        {:subscribe, sub_list} = req.request
        # Should have 2 subscription entries (one per path)
        assert length(sub_list.subscription) == 2
        :ok
      end)
      |> stub(:end_stream, fn :fake_stream -> :fake_stream end)
      |> expect(:recv, fn :fake_stream -> {:error, :test_exit} end)

      {:noreply, _new_state} = GnmiSession.handle_info(:subscribe, state)

      Process.sleep(50)
    end
  end

  describe "handle_info :stream_ended" do
    test "clears stream and task_ref, schedules retry" do
      device = create_device()
      ref = make_ref()
      state = make_state(device, channel: :fake_channel, stream: :fake_stream, task_ref: ref)

      {:noreply, new_state} = GnmiSession.handle_info({ref, :stream_ended}, state)

      assert new_state.stream == nil
      assert new_state.task_ref == nil
      # Channel should remain (we want to reconnect the subscription, not the gRPC channel)
      assert new_state.channel == :fake_channel
    end

    test "does not match when ref differs" do
      device = create_device()
      real_ref = make_ref()
      other_ref = make_ref()
      state = make_state(device, channel: :ch, stream: :st, task_ref: real_ref)

      # Mismatched ref should hit the catch-all handler
      {:noreply, new_state} = GnmiSession.handle_info({other_ref, :stream_ended}, state)

      # State should be unchanged (catch-all returns state as-is)
      assert new_state.stream == :st
      assert new_state.task_ref == real_ref
    end
  end

  describe "handle_info DOWN (task crash)" do
    test "clears stream and task_ref, schedules retry" do
      device = create_device()
      ref = make_ref()
      state = make_state(device, channel: :fake_channel, stream: :fake_stream, task_ref: ref)

      {:noreply, new_state} =
        GnmiSession.handle_info({:DOWN, ref, :process, self(), :crash}, state)

      assert new_state.stream == nil
      assert new_state.task_ref == nil
    end

    test "does not match when ref differs" do
      device = create_device()
      real_ref = make_ref()
      other_ref = make_ref()
      state = make_state(device, channel: :ch, stream: :st, task_ref: real_ref)

      {:noreply, new_state} =
        GnmiSession.handle_info({:DOWN, other_ref, :process, self(), :crash}, state)

      # Catch-all: state unchanged
      assert new_state.stream == :st
      assert new_state.task_ref == real_ref
    end
  end

  describe "terminate/2" do
    test "disconnects channel when present" do
      device = create_device()
      state = make_state(device, channel: :fake_channel)

      MockGrpcClient
      |> expect(:disconnect, fn :fake_channel -> {:ok, :fake_channel} end)

      assert :ok = GnmiSession.terminate(:normal, state)
    end

    test "no-op when channel is nil" do
      device = create_device()
      state = make_state(device, channel: nil)

      # No mock expectations -- disconnect must not be called
      assert :ok = GnmiSession.terminate(:normal, state)
    end

    test "disconnects on shutdown reason" do
      device = create_device()
      state = make_state(device, channel: :fake_channel)

      MockGrpcClient
      |> expect(:disconnect, fn :fake_channel -> {:ok, :fake_channel} end)

      assert :ok = GnmiSession.terminate(:shutdown, state)
    end
  end

  describe "retry backoff" do
    test "successful connect resets retry_count to 0" do
      device = create_device()
      state = make_state(device, retry_count: 5)

      MockGrpcClient
      |> expect(:connect, fn _, _ -> {:ok, :channel} end)

      {:noreply, new_state} = GnmiSession.handle_info(:connect, state)
      assert new_state.retry_count == 0
    end

    test "failure from retry_count 0 goes to 1" do
      device = create_device()
      state = make_state(device, retry_count: 0)

      MockGrpcClient
      |> expect(:connect, fn _, _ -> {:error, :refused} end)

      {:noreply, new_state} = GnmiSession.handle_info(:connect, state)
      assert new_state.retry_count == 1
    end

    test "failure from retry_count 3 goes to 4" do
      device = create_device()
      state = make_state(device, retry_count: 3)

      MockGrpcClient
      |> expect(:connect, fn _, _ -> {:error, :refused} end)

      {:noreply, new_state} = GnmiSession.handle_info(:connect, state)
      assert new_state.retry_count == 4
    end
  end

  describe "catch-all handle_info" do
    test "unknown messages do not crash the GenServer" do
      device = create_device()
      state = make_state(device)

      {:noreply, returned_state} = GnmiSession.handle_info(:unexpected_message, state)
      assert returned_state == state
    end
  end
end

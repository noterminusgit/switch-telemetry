defmodule SwitchTelemetry.Collector.NetconfSessionLifecycleTest do
  @moduledoc """
  Tests the GenServer lifecycle callbacks of NetconfSession by invoking
  handle_info/terminate directly with Mox-based mock expectations.
  """
  use SwitchTelemetry.DataCase, async: false

  import Mox

  alias SwitchTelemetry.Collector.NetconfSession
  alias SwitchTelemetry.Collector.MockSshClient
  alias SwitchTelemetry.{Collector, Devices}

  setup :verify_on_exit!

  setup do
    Application.put_env(:switch_telemetry, :ssh_client, MockSshClient)
    on_exit(fn -> Application.delete_env(:switch_telemetry, :ssh_client) end)
    :ok
  end

  # -- Fixture helpers --

  defp unique_int, do: System.unique_integer([:positive])

  defp create_credential(overrides \\ %{}) do
    n = unique_int()

    attrs =
      Map.merge(
        %{
          id: "cred-#{n}",
          name: "credential-#{n}",
          username: "admin",
          password: "secret123"
        },
        overrides
      )

    {:ok, credential} = Devices.create_credential(attrs)
    credential
  end

  defp create_device(overrides \\ %{}) do
    n = unique_int()

    # Ensure credential exists if credential_id is provided
    credential_id =
      case Map.get(overrides, :credential_id) do
        nil ->
          cred = create_credential()
          cred.id

        id ->
          id
      end

    attrs =
      Map.merge(
        %{
          id: "dev-#{n}",
          hostname: "switch-#{n}",
          ip_address: "10.1.#{rem(n, 254) + 1}.#{rem(n, 253) + 1}",
          platform: :cisco_iosxr,
          transport: :netconf,
          netconf_port: 830,
          collection_interval_ms: 30_000,
          credential_id: credential_id
        },
        overrides
      )

    {:ok, device} = Devices.create_device(attrs)
    device
  end

  defp create_device_with_credential(device_overrides \\ %{}, cred_overrides \\ %{}) do
    credential = create_credential(cred_overrides)
    device = create_device(Map.put(device_overrides, :credential_id, credential.id))
    {device, credential}
  end

  defp create_subscription(device, paths) do
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
    defaults = %NetconfSession{
      device: device,
      ssh_ref: nil,
      channel_id: nil,
      timer_ref: nil,
      buffer: "",
      message_id: 1
    }

    struct!(defaults, overrides)
  end

  # -- Tests --

  describe "init/1" do
    test "sets trap_exit, sends :connect, initializes buffer and message_id" do
      {device, _credential} = create_device_with_credential()
      {:ok, state} = NetconfSession.init(device: device)

      assert state.device.id == device.id
      assert state.buffer == ""
      assert state.message_id == 1
      assert state.ssh_ref == nil
      assert state.channel_id == nil
      assert state.timer_ref == nil
      assert_received :connect
    end
  end

  describe "handle_info :connect" do
    test "success establishes SSH session and starts timer" do
      {device, _credential} = create_device_with_credential()
      state = make_state(device)

      test_pid = self()

      MockSshClient
      |> expect(:connect, fn host, port, opts ->
        assert host == String.to_charlist(device.ip_address)
        assert port == device.netconf_port
        assert Keyword.get(opts, :user) == ~c"admin"
        assert Keyword.get(opts, :password) == ~c"secret123"
        assert Keyword.get(opts, :silently_accept_hosts) == true
        {:ok, test_pid}
      end)
      |> expect(:session_channel, fn ^test_pid, 30_000 -> {:ok, 0} end)
      |> expect(:subsystem, fn ^test_pid, 0, ~c"netconf", 30_000 -> :success end)
      |> expect(:send, fn ^test_pid, 0, hello_data ->
        assert hello_data =~ "hello"
        assert hello_data =~ "netconf"
        :ok
      end)

      {:noreply, new_state} = NetconfSession.handle_info(:connect, state)

      assert new_state.ssh_ref == test_pid
      assert new_state.channel_id == 0
      assert new_state.timer_ref != nil

      # Clean up the timer to avoid leaking
      :timer.cancel(new_state.timer_ref)
    end

    test "success updates device status to active" do
      {device, _credential} = create_device_with_credential(%{status: :unreachable})
      state = make_state(device)

      test_pid = self()

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, test_pid} end)
      |> expect(:session_channel, fn _ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn _ref, _channel, _sub, _timeout -> :success end)
      |> expect(:send, fn _ref, _channel, _data -> :ok end)

      {:noreply, new_state} = NetconfSession.handle_info(:connect, state)

      updated_device = Devices.get_device!(device.id)
      assert updated_device.status == :active
      assert updated_device.last_seen_at != nil

      :timer.cancel(new_state.timer_ref)
    end

    test "success without password in credential" do
      {device, _credential} = create_device_with_credential(%{}, %{password: nil})

      state = make_state(device)
      test_pid = self()

      MockSshClient
      |> expect(:connect, fn _host, _port, opts ->
        refute Keyword.has_key?(opts, :password)
        {:ok, test_pid}
      end)
      |> expect(:session_channel, fn _ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn _ref, _channel, _sub, _timeout -> :success end)
      |> expect(:send, fn _ref, _channel, _data -> :ok end)

      {:noreply, new_state} = NetconfSession.handle_info(:connect, state)

      assert new_state.ssh_ref == test_pid
      :timer.cancel(new_state.timer_ref)
    end

    test "connect failure schedules reconnect after 10s" do
      {device, _credential} = create_device_with_credential()
      state = make_state(device)

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:error, :econnrefused} end)

      {:noreply, new_state} = NetconfSession.handle_info(:connect, state)

      assert new_state.ssh_ref == nil
      assert new_state.channel_id == nil
    end

    test "connect failure updates device status to unreachable" do
      {device, _credential} = create_device_with_credential(%{status: :active})
      state = make_state(device)

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:error, :timeout} end)

      {:noreply, _new_state} = NetconfSession.handle_info(:connect, state)

      updated_device = Devices.get_device!(device.id)
      assert updated_device.status == :unreachable
    end

    test "session_channel failure schedules reconnect" do
      {device, _credential} = create_device_with_credential()
      state = make_state(device)

      test_pid = self()

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, test_pid} end)
      |> expect(:session_channel, fn _ref, _timeout -> {:error, :channel_open_failed} end)

      {:noreply, new_state} = NetconfSession.handle_info(:connect, state)

      # Connection failed at session_channel step, so state should remain disconnected
      assert new_state.ssh_ref == nil
    end

    test "subsystem failure schedules reconnect" do
      {device, _credential} = create_device_with_credential()
      state = make_state(device)

      test_pid = self()

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, test_pid} end)
      |> expect(:session_channel, fn _ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn _ref, _channel, _sub, _timeout -> :failure end)

      {:noreply, new_state} = NetconfSession.handle_info(:connect, state)

      assert new_state.ssh_ref == nil
    end
  end

  describe "handle_info :collect" do
    test "no-op when ssh_ref is nil" do
      device = create_device()
      state = make_state(device, ssh_ref: nil)

      {:noreply, returned_state} = NetconfSession.handle_info(:collect, state)
      assert returned_state == state
    end

    test "sends RPCs for each subscription path and increments message_id" do
      {device, _credential} = create_device_with_credential()
      _sub = create_subscription(device, ["/interfaces/interface/state/counters"])

      test_pid = self()
      state = make_state(device, ssh_ref: test_pid, channel_id: 0)

      MockSshClient
      |> expect(:send, fn ^test_pid, 0, rpc_data ->
        assert rpc_data =~ "message-id="
        assert rpc_data =~ "<get>"
        assert rpc_data =~ "<filter type=\"subtree\">"
        :ok
      end)

      {:noreply, new_state} = NetconfSession.handle_info(:collect, state)

      assert new_state.message_id == 2
    end

    test "sends one RPC per path across multiple subscriptions" do
      {device, _credential} = create_device_with_credential()
      _sub1 = create_subscription(device, ["/interfaces/interface/state/counters"])
      _sub2 = create_subscription(device, ["/system/state/hostname"])

      test_pid = self()
      state = make_state(device, ssh_ref: test_pid, channel_id: 0, message_id: 1)

      MockSshClient
      |> expect(:send, 2, fn ^test_pid, 0, _rpc_data -> :ok end)

      {:noreply, new_state} = NetconfSession.handle_info(:collect, state)

      # 2 paths => 2 RPCs => message_id incremented by 2
      assert new_state.message_id == 3
    end

    test "does nothing when no subscriptions exist" do
      {device, _credential} = create_device_with_credential()
      # No subscriptions created

      test_pid = self()
      state = make_state(device, ssh_ref: test_pid, channel_id: 0, message_id: 1)

      # No send expectations -- no RPCs should be sent

      {:noreply, new_state} = NetconfSession.handle_info(:collect, state)

      # message_id should not change since no paths
      assert new_state.message_id == 1
    end
  end

  describe "handle_info SSH data" do
    test "appends partial data to buffer" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0, buffer: "")

      {:noreply, new_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:data, 0, 0, "partial data"}},
          state
        )

      assert new_state.buffer == "partial data"
    end

    test "accumulates data across multiple messages" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0, buffer: "first ")

      {:noreply, new_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:data, 0, 0, "second"}},
          state
        )

      assert new_state.buffer == "first second"
    end

    test "extracts complete message and keeps remainder in buffer" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0, buffer: "")

      {:noreply, new_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:data, 0, 0, "<rpc-reply/>]]>]]>remaining"}},
          state
        )

      assert new_state.buffer == "remaining"
    end

    test "handles binary chardata conversion" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0, buffer: "")

      {:noreply, new_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:data, 0, 0, ~c"charlist data"}},
          state
        )

      assert new_state.buffer == "charlist data"
    end
  end

  describe "handle_info SSH closed" do
    test "cleans up SSH, clears state, schedules reconnect" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0, buffer: "data", message_id: 5)

      MockSshClient
      |> expect(:close, fn _ref -> :ok end)

      {:noreply, new_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:closed, 0}},
          state
        )

      assert new_state.ssh_ref == nil
      assert new_state.channel_id == nil
      assert new_state.buffer == ""
      # message_id is NOT reset by the closed handler
    end

    test "cancels timer on close when timer_ref is set" do
      device = create_device()
      {:ok, timer_ref} = :timer.send_interval(600_000, :dummy)
      state = make_state(device, ssh_ref: self(), channel_id: 0, timer_ref: timer_ref, buffer: "")

      MockSshClient
      |> expect(:close, fn _ref -> :ok end)

      {:noreply, _new_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:closed, 0}},
          state
        )

      # Timer should have been cancelled -- no :dummy messages expected
      refute_receive :dummy, 100
    end
  end

  describe "handle_info SSH exit_status and eof" do
    test "exit_status is a no-op" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0)

      {:noreply, returned_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:exit_status, 0, 0}},
          state
        )

      assert returned_state == state
    end

    test "eof is a no-op" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0)

      {:noreply, returned_state} =
        NetconfSession.handle_info(
          {:ssh_cm, self(), {:eof, 0}},
          state
        )

      assert returned_state == state
    end
  end

  describe "terminate/2" do
    test "cancels timer and closes SSH when both are present" do
      device = create_device()
      {:ok, timer_ref} = :timer.send_interval(600_000, :dummy)

      state = make_state(device, ssh_ref: self(), channel_id: 0, timer_ref: timer_ref)

      MockSshClient
      |> expect(:close, fn _ref -> :ok end)

      assert :ok = NetconfSession.terminate(:normal, state)

      # Verify timer was cancelled
      refute_receive :dummy, 100
    end

    test "handles nil ssh_ref and timer_ref gracefully" do
      device = create_device()
      state = make_state(device, ssh_ref: nil, channel_id: nil, timer_ref: nil)

      # No mock expectations -- close should not be called
      assert :ok = NetconfSession.terminate(:normal, state)
    end

    test "closes SSH only when timer_ref is nil" do
      device = create_device()
      state = make_state(device, ssh_ref: self(), channel_id: 0, timer_ref: nil)

      MockSshClient
      |> expect(:close, fn _ref -> :ok end)

      assert :ok = NetconfSession.terminate(:shutdown, state)
    end

    test "cancels timer only when ssh_ref is nil" do
      device = create_device()
      {:ok, timer_ref} = :timer.send_interval(600_000, :dummy)
      state = make_state(device, ssh_ref: nil, channel_id: nil, timer_ref: timer_ref)

      # No close expectation -- ssh_ref is nil
      assert :ok = NetconfSession.terminate(:normal, state)

      refute_receive :dummy, 100
    end
  end

  describe "catch-all handle_info" do
    test "unknown messages do not crash" do
      device = create_device()
      state = make_state(device)

      {:noreply, returned_state} = NetconfSession.handle_info(:unexpected, state)
      assert returned_state == state
    end
  end
end

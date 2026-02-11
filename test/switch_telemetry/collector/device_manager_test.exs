defmodule SwitchTelemetry.Collector.DeviceManagerTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.DeviceManager

  describe "module" do
    test "exports start_link/1" do
      assert function_exported?(DeviceManager, :start_link, 1)
    end

    test "exports start_device_session/1" do
      assert function_exported?(DeviceManager, :start_device_session, 1)
    end

    test "exports stop_device_session/1" do
      assert function_exported?(DeviceManager, :stop_device_session, 1)
    end

    test "exports list_sessions/0" do
      assert function_exported?(DeviceManager, :list_sessions, 0)
    end
  end
end

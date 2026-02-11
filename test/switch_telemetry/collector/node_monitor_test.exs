defmodule SwitchTelemetry.Collector.NodeMonitorTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.NodeMonitor

  describe "module" do
    test "exports start_link/1" do
      assert function_exported?(NodeMonitor, :start_link, 1)
    end

    test "exports cluster_status/0" do
      assert function_exported?(NodeMonitor, :cluster_status, 0)
    end
  end
end

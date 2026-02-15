defmodule SwitchTelemetry.ApplicationTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Application

  describe "common_children/0" do
    test "includes Repo" do
      children = Application.common_children()
      assert SwitchTelemetry.Repo in children
    end

    test "includes InfluxDB" do
      children = Application.common_children()
      assert SwitchTelemetry.InfluxDB in children
    end

    test "includes Vault" do
      children = Application.common_children()
      assert SwitchTelemetry.Vault in children
    end

    test "includes PubSub, Horde, and Finch" do
      children = Application.common_children()

      modules = extract_modules(children)

      assert Phoenix.PubSub in modules
      assert Horde.Registry in modules
      assert Horde.DynamicSupervisor in modules
      assert Finch in modules
    end
  end

  describe "collector_children/1" do
    test "returns collector modules for 'collector' role" do
      children = Application.collector_children("collector")
      assert length(children) > 0

      modules = extract_modules(children)

      assert SwitchTelemetry.Collector.DeviceAssignment in modules
      assert SwitchTelemetry.Collector.NodeMonitor in modules
      assert SwitchTelemetry.Collector.DeviceManager in modules
      assert SwitchTelemetry.Collector.StreamMonitor in modules
    end

    test "returns collector modules for 'both' role" do
      children = Application.collector_children("both")
      assert length(children) > 0

      modules = extract_modules(children)

      assert SwitchTelemetry.Collector.DeviceAssignment in modules
    end

    test "returns empty list for 'web' role" do
      assert Application.collector_children("web") == []
    end

    test "returns empty list for unknown role" do
      assert Application.collector_children("unknown") == []
    end
  end

  describe "web_children/1" do
    test "returns web modules for 'web' role" do
      children = Application.web_children("web")
      assert length(children) > 0

      modules = extract_modules(children)

      assert SwitchTelemetryWeb.Telemetry in modules
      assert SwitchTelemetryWeb.Endpoint in modules
    end

    test "returns web modules for 'both' role" do
      children = Application.web_children("both")
      assert length(children) > 0
    end

    test "returns empty list for 'collector' role" do
      assert Application.web_children("collector") == []
    end
  end

  # Helper to extract modules from child specs (handles both bare atoms and tuples)
  defp extract_modules(children) do
    Enum.map(children, fn
      {module, _opts} -> module
      module when is_atom(module) -> module
    end)
  end
end

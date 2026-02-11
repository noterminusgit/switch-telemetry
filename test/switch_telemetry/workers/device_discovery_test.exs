defmodule SwitchTelemetry.Workers.DeviceDiscoveryTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Workers.DeviceDiscovery

  describe "module" do
    test "uses Oban.Worker" do
      assert {:module, DeviceDiscovery} = Code.ensure_loaded(DeviceDiscovery)
      # Oban workers implement perform/1
      assert DeviceDiscovery.__info__(:functions) |> Keyword.has_key?(:perform)
    end

    test "perform succeeds with no devices" do
      assert :ok == DeviceDiscovery.perform(%Oban.Job{})
    end
  end
end

defmodule SwitchTelemetry.Workers.AlertEvaluatorTest do
  use SwitchTelemetry.DataCase, async: true
  use Oban.Testing, repo: SwitchTelemetry.Repo

  alias SwitchTelemetry.Workers.AlertEvaluator
  alias SwitchTelemetry.Alerting

  describe "enqueue" do
    test "worker can be enqueued" do
      assert {:ok, _} =
               AlertEvaluator.new(%{})
               |> Oban.insert()
    end
  end

  describe "perform/1" do
    test "returns :ok when no enabled rules exist" do
      assert :ok == perform_job(AlertEvaluator, %{})
    end

    test "returns :ok with an enabled rule that has no matching metrics" do
      # Create a device first so FK constraint is satisfied
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "test-router",
          ip_address: "10.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _rule} =
        Alerting.create_alert_rule(%{
          name: "Test CPU Alert",
          path: "/interfaces/interface/state/counters/in-octets",
          condition: :above,
          threshold: 90.0,
          duration_seconds: 60,
          cooldown_seconds: 300,
          severity: :warning,
          enabled: true,
          device_id: device.id
        })

      assert :ok == perform_job(AlertEvaluator, %{})
    end
  end
end

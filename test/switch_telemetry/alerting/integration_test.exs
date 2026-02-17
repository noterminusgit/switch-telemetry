defmodule SwitchTelemetry.Alerting.IntegrationTest do
  use SwitchTelemetry.DataCase, async: false
  use Oban.Testing, repo: SwitchTelemetry.Repo

  @moduletag :influx

  alias SwitchTelemetry.{Alerting, Devices, Metrics}
  alias SwitchTelemetry.Workers.AlertEvaluator

  setup do
    # Create a device
    {:ok, device} =
      Devices.create_device(%{
        id: Ecto.UUID.generate(),
        hostname: "integration-test-router-#{System.unique_integer([:positive])}",
        ip_address: "10.99.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
        platform: :cisco_iosxr,
        transport: :gnmi
      })

    # Create an alert rule with cooldown 0 so transitions happen immediately
    {:ok, rule} =
      Alerting.create_alert_rule(%{
        name: "integration-test-#{System.unique_integer([:positive])}",
        path: "cpu/usage",
        condition: :above,
        threshold: 90.0,
        duration_seconds: 60,
        cooldown_seconds: 0,
        severity: :critical,
        device_id: device.id
      })

    %{device: device, rule: rule}
  end

  test "full lifecycle: no metrics -> ok, high metrics -> firing, low metrics -> resolved", ctx do
    # 1. No metrics — :above condition with no metrics stays ok
    assert :ok == perform_job(AlertEvaluator, %{})
    rule = Alerting.get_alert_rule!(ctx.rule.id)
    assert rule.state == :ok

    # 2. Insert high metrics
    now = DateTime.utc_now()

    metrics =
      for i <- 0..4 do
        %{
          time: DateTime.add(now, -i, :second),
          device_id: ctx.device.id,
          path: "cpu/usage",
          source: "gnmi",
          value_float: 95.0
        }
      end

    Metrics.insert_batch(metrics)
    Process.sleep(1000)

    # 3. Run evaluator — should fire
    assert :ok == perform_job(AlertEvaluator, %{})
    rule = Alerting.get_alert_rule!(ctx.rule.id)
    assert rule.state == :firing
    assert rule.last_fired_at != nil

    # Verify event was created
    events = Alerting.list_events(rule.id)
    assert length(events) >= 1
    firing_event = Enum.find(events, &(&1.status == :firing))
    assert firing_event != nil
    assert firing_event.value == 95.0

    # 4. Run evaluator again while still firing — should NOT create duplicate
    assert :ok == perform_job(AlertEvaluator, %{})
    events_after = Alerting.list_events(rule.id)
    firing_events = Enum.filter(events_after, &(&1.status == :firing))
    assert length(firing_events) == 1

    # 5. Insert low metrics (newer timestamps so they come first in the query)
    low_metrics =
      for i <- 0..4 do
        %{
          time: DateTime.add(DateTime.utc_now(), -i, :second),
          device_id: ctx.device.id,
          path: "cpu/usage",
          source: "gnmi",
          value_float: 50.0
        }
      end

    Metrics.insert_batch(low_metrics)
    Process.sleep(1000)

    # 6. Run evaluator — should resolve
    assert :ok == perform_job(AlertEvaluator, %{})
    rule = Alerting.get_alert_rule!(ctx.rule.id)
    assert rule.state == :ok
    assert rule.last_resolved_at != nil

    resolved_events =
      Alerting.list_events(rule.id) |> Enum.filter(&(&1.status == :resolved))

    assert length(resolved_events) >= 1
  end
end

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

  describe "perform/1 firing with :absent condition" do
    setup do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "absent-data-router",
          ip_address: "10.0.3.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      %{device: device}
    end

    test "fires alert for :absent condition when no metrics exist", %{device: device} do
      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "Absent Data Alert",
          path: "/interfaces/interface/state/oper-status",
          condition: :absent,
          threshold: 0.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :critical,
          enabled: true,
          device_id: device.id,
          state: :ok
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      # Rule state should transition to :firing
      updated_rule = Alerting.get_alert_rule!(rule.id)
      assert updated_rule.state == :firing
      assert updated_rule.last_fired_at != nil
    end

    test "creates an alert event when firing", %{device: device} do
      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "Absent Event Creation",
          path: "/interfaces/interface/state/oper-status",
          condition: :absent,
          threshold: 0.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :critical,
          enabled: true,
          device_id: device.id,
          state: :ok
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      events = Alerting.list_events(rule.id)
      assert length(events) == 1
      [event] = events
      assert event.status == :firing
      assert event.alert_rule_id == rule.id
      assert event.device_id == device.id
    end

    test "broadcasts alert event on PubSub when firing", %{device: device} do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "alerts")

      {:ok, _rule} =
        Alerting.create_alert_rule(%{
          name: "PubSub Broadcast Alert",
          path: "/interfaces/interface/state/oper-status",
          condition: :absent,
          threshold: 0.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :critical,
          enabled: true,
          device_id: device.id,
          state: :ok
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      assert_receive {:alert_event, event}, 1000
      assert event.status == :firing
    end

    test "also broadcasts to device-specific alert topic when firing", %{device: device} do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "alerts:#{device.id}")

      {:ok, _rule} =
        Alerting.create_alert_rule(%{
          name: "Device PubSub Alert",
          path: "/interfaces/interface/state/oper-status",
          condition: :absent,
          threshold: 0.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :critical,
          enabled: true,
          device_id: device.id,
          state: :ok
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      assert_receive {:alert_event, event}, 1000
      assert event.device_id == device.id
    end

    test "triggers notification for bound channels on firing", %{device: device} do
      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "Notifier Enqueue Alert",
          path: "/interfaces/interface/state/oper-status",
          condition: :absent,
          threshold: 0.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :critical,
          enabled: true,
          device_id: device.id,
          state: :ok
        })

      {:ok, channel} =
        Alerting.create_channel(%{
          name: "Evaluator Test Webhook",
          type: :webhook,
          config: %{"url" => "http://localhost:19999/test-webhook"}
        })

      {:ok, _binding} = Alerting.bind_channel(rule.id, channel.id)

      # Verify the channel is bound to the rule
      channels = Alerting.list_channels_for_rule(rule.id)
      assert length(channels) == 1
      assert hd(channels).id == channel.id

      # perform_job runs inline; with testing: :inline, the AlertNotifier job
      # is executed immediately (shown by the econnrefused log for the webhook).
      # We verify the alert event was created, which is the prerequisite
      # for notification dispatch.
      assert :ok == perform_job(AlertEvaluator, %{})

      events = Alerting.list_events(rule.id)
      assert length(events) == 1
      [event] = events
      assert event.status == :firing
      assert event.device_id == device.id
    end
  end

  describe "perform/1 resolved transition" do
    test "resolves a firing rule when condition is no longer met" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "resolve-router",
          ip_address: "10.0.4.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      # Rule is in :firing state with :above condition
      # Since there are no metrics, extract_value returns nil,
      # check_condition(:above, nil, _) returns :ok,
      # and since rule.state == :firing, it resolves
      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "Resolve Test Alert",
          path: "/interfaces/interface/state/counters/in-octets",
          condition: :above,
          threshold: 90.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :warning,
          enabled: true,
          device_id: device.id,
          state: :firing,
          last_fired_at: DateTime.utc_now()
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      updated_rule = Alerting.get_alert_rule!(rule.id)
      assert updated_rule.state == :ok
      assert updated_rule.last_resolved_at != nil
    end

    test "creates a resolved alert event" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "resolve-event-router",
          ip_address: "10.0.4.2",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "Resolve Event Alert",
          path: "/interfaces/interface/state/counters/in-octets",
          condition: :above,
          threshold: 90.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :warning,
          enabled: true,
          device_id: device.id,
          state: :firing,
          last_fired_at: DateTime.utc_now()
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      events = Alerting.list_events(rule.id)
      assert length(events) == 1
      [event] = events
      assert event.status == :resolved
      assert event.message =~ "resolved"
    end

    test "broadcasts resolved event on PubSub" do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "alerts")

      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "resolve-pubsub-router",
          ip_address: "10.0.4.3",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _rule} =
        Alerting.create_alert_rule(%{
          name: "Resolve PubSub Alert",
          path: "/interfaces/interface/state/counters/in-octets",
          condition: :above,
          threshold: 90.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :warning,
          enabled: true,
          device_id: device.id,
          state: :firing,
          last_fired_at: DateTime.utc_now()
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      assert_receive {:alert_event, event}, 1000
      assert event.status == :resolved
    end
  end

  describe "perform/1 no state change" do
    test "does not fire when rule is already firing (no duplicate)" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "already-firing-router",
          ip_address: "10.0.5.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "Already Firing Alert",
          path: "/interfaces/interface/state/oper-status",
          condition: :absent,
          threshold: 0.0,
          duration_seconds: 60,
          cooldown_seconds: 0,
          severity: :critical,
          enabled: true,
          device_id: device.id,
          state: :firing,
          last_fired_at: DateTime.utc_now()
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      # No new events should be created (rule was already firing and absent still fires,
      # but evaluate_rule returns :ok when state is already :firing)
      events = Alerting.list_events(rule.id)
      assert events == []
    end

    test "does nothing when :ok state and :above condition with no metrics" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "ok-no-change-router",
          ip_address: "10.0.5.2",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, rule} =
        Alerting.create_alert_rule(%{
          name: "No Change Alert",
          path: "/interfaces/interface/state/counters/in-octets",
          condition: :above,
          threshold: 90.0,
          duration_seconds: 60,
          cooldown_seconds: 300,
          severity: :warning,
          enabled: true,
          device_id: device.id,
          state: :ok
        })

      assert :ok == perform_job(AlertEvaluator, %{})

      # Rule state should remain :ok
      updated_rule = Alerting.get_alert_rule!(rule.id)
      assert updated_rule.state == :ok

      # No events should be created
      events = Alerting.list_events(rule.id)
      assert events == []
    end
  end
end

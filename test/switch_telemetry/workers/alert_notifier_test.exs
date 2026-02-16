defmodule SwitchTelemetry.Workers.AlertNotifierTest do
  use SwitchTelemetry.DataCase, async: true
  use Oban.Testing, repo: SwitchTelemetry.Repo

  alias SwitchTelemetry.Workers.AlertNotifier

  describe "module" do
    test "uses Oban.Worker" do
      assert {:module, AlertNotifier} = Code.ensure_loaded(AlertNotifier)
      assert AlertNotifier.__info__(:functions) |> Keyword.has_key?(:perform)
    end

    test "is configured for the notifications queue" do
      assert AlertNotifier.__opts__()[:queue] == :notifications
    end

    test "has max_attempts of 5" do
      assert AlertNotifier.__opts__()[:max_attempts] == 5
    end
  end

  describe "enqueueing" do
    test "can build a valid job changeset" do
      changeset =
        AlertNotifier.new(%{
          "alert_event_id" => "evt_1",
          "channel_id" => "ch_1"
        })

      assert changeset.valid?
      assert changeset.changes.args == %{"alert_event_id" => "evt_1", "channel_id" => "ch_1"}
    end

    test "job changeset has correct queue" do
      changeset =
        AlertNotifier.new(%{
          "alert_event_id" => "evt_123",
          "channel_id" => "ch_456"
        })

      assert changeset.valid?
      assert changeset.changes.queue == "notifications"
    end

    test "job changeset has correct worker" do
      changeset =
        AlertNotifier.new(%{
          "alert_event_id" => "evt_123",
          "channel_id" => "ch_456"
        })

      assert changeset.valid?
      assert changeset.changes.worker == "SwitchTelemetry.Workers.AlertNotifier"
    end
  end

  describe "perform/1" do
    setup do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "test-notif-router",
          ip_address: "10.0.0.99",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, rule} =
        SwitchTelemetry.Alerting.create_alert_rule(%{
          name: "Notifier Test Alert",
          path: "/test/notifier/path",
          condition: :above,
          threshold: 90.0,
          duration_seconds: 60,
          cooldown_seconds: 300,
          severity: :warning,
          enabled: true,
          device_id: device.id
        })

      {:ok, event} =
        SwitchTelemetry.Alerting.create_event(%{
          alert_rule_id: rule.id,
          device_id: device.id,
          status: :firing,
          value: 95.0,
          message: "Test alert message for notifier"
        })

      %{device: device, rule: rule, event: event}
    end

    test "webhook channel returns error when HTTP connection fails", %{event: event} do
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Test Webhook Channel",
          type: :webhook,
          config: %{"url" => "http://localhost:19999/webhook"}
        })

      result =
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => channel.id}
        })

      assert {:error, _reason} = result
    end

    test "slack channel returns error when HTTP connection fails", %{event: event} do
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Test Slack Channel",
          type: :slack,
          config: %{"url" => "http://localhost:19999/slack-hook"}
        })

      result =
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => channel.id}
        })

      assert {:error, _reason} = result
    end

    test "email channel delivers via Swoosh test adapter", %{event: event} do
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Test Email Channel",
          type: :email,
          config: %{
            "to" => "admin@example.com",
            "from" => "alerts@switchtelemetry.local"
          }
        })

      result =
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => channel.id}
        })

      assert result == :ok
    end

    test "raises Ecto.NoResultsError for invalid event_id" do
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Channel For Missing Event",
          type: :webhook,
          config: %{"url" => "http://localhost:19999/webhook"}
        })

      assert_raise Ecto.NoResultsError, fn ->
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => Ecto.UUID.generate(), "channel_id" => channel.id}
        })
      end
    end

    test "raises Ecto.NoResultsError for invalid channel_id", %{event: event} do
      assert_raise Ecto.NoResultsError, fn ->
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => Ecto.UUID.generate()}
        })
      end
    end

    test "webhook channel with unreachable host returns connection error", %{event: event} do
      # Use a URL that will refuse connection (non-routable IP with very high port)
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Unreachable Webhook",
          type: :webhook,
          config: %{"url" => "http://192.0.2.1:1/webhook"}
        })

      result =
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => channel.id}
        })

      assert {:error, _reason} = result
    end

    test "slack channel with unreachable host returns connection error", %{event: event} do
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Unreachable Slack",
          type: :slack,
          config: %{"url" => "http://192.0.2.1:1/slack"}
        })

      result =
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => channel.id}
        })

      assert {:error, _reason} = result
    end

    test "email channel with valid config succeeds via Swoosh test adapter", %{event: event} do
      {:ok, channel} =
        SwitchTelemetry.Alerting.create_channel(%{
          name: "Email With From",
          type: :email,
          config: %{
            "to" => "ops@example.com",
            "from" => "noreply@switchtelemetry.local"
          }
        })

      result =
        AlertNotifier.perform(%Oban.Job{
          args: %{"alert_event_id" => event.id, "channel_id" => channel.id}
        })

      assert result == :ok
    end
  end

  describe "job construction" do
    test "builds job with custom args" do
      args = %{
        "alert_event_id" => Ecto.UUID.generate(),
        "channel_id" => Ecto.UUID.generate()
      }

      changeset = AlertNotifier.new(args)
      assert changeset.valid?
      assert changeset.changes.args == args
      assert changeset.changes.max_attempts == 5
    end
  end
end

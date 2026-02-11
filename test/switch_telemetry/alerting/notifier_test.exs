defmodule SwitchTelemetry.Alerting.NotifierTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Alerting.Notifier

  @rule %{
    name: "High CPU",
    severity: :critical,
    path: "cpu/usage",
    condition: :above,
    threshold: 90.0
  }

  @event %{
    status: :firing,
    device_id: "dev_1",
    value: 95.0,
    message: "CPU at 95%",
    inserted_at: ~U[2024-01-01 00:00:00Z]
  }

  describe "format_webhook_payload/2" do
    test "returns map with all required keys" do
      payload = Notifier.format_webhook_payload(@event, @rule)

      assert payload["alert_rule"] == "High CPU"
      assert payload["severity"] == "critical"
      assert payload["status"] == "firing"
      assert payload["device_id"] == "dev_1"
      assert payload["path"] == "cpu/usage"
      assert payload["value"] == 95.0
      assert payload["message"] == "CPU at 95%"
      assert payload["fired_at"] == "2024-01-01T00:00:00Z"
    end

    test "converts severity atom to string" do
      rule = %{@rule | severity: :warning}
      payload = Notifier.format_webhook_payload(@event, rule)
      assert payload["severity"] == "warning"
    end

    test "converts status atom to string" do
      event = %{@event | status: :resolved}
      payload = Notifier.format_webhook_payload(event, @rule)
      assert payload["status"] == "resolved"
    end
  end

  describe "format_slack_payload/2" do
    test "returns valid Block Kit structure with three blocks" do
      payload = Notifier.format_slack_payload(@event, @rule)
      blocks = payload["blocks"]

      assert length(blocks) == 3
      assert Enum.at(blocks, 0)["type"] == "header"
      assert Enum.at(blocks, 1)["type"] == "section"
      assert Enum.at(blocks, 2)["type"] == "section"
    end

    test "header includes red_circle emoji for critical severity" do
      payload = Notifier.format_slack_payload(@event, @rule)
      header = Enum.at(payload["blocks"], 0)
      assert header["text"]["text"] == ":red_circle: Alert: High CPU"
    end

    test "header includes large_orange_circle emoji for warning severity" do
      rule = %{@rule | severity: :warning}
      payload = Notifier.format_slack_payload(@event, rule)
      header = Enum.at(payload["blocks"], 0)
      assert header["text"]["text"] == ":large_orange_circle: Alert: High CPU"
    end

    test "header includes large_blue_circle emoji for info severity" do
      rule = %{@rule | severity: :info}
      payload = Notifier.format_slack_payload(@event, rule)
      header = Enum.at(payload["blocks"], 0)
      assert header["text"]["text"] == ":large_blue_circle: Alert: High CPU"
    end

    test "section fields include severity, status, device, and path" do
      payload = Notifier.format_slack_payload(@event, @rule)
      fields = Enum.at(payload["blocks"], 1)["fields"]

      assert length(fields) == 4
      assert Enum.at(fields, 0)["text"] == "*Severity:*\ncritical"
      assert Enum.at(fields, 1)["text"] == "*Status:*\nfiring"
      assert Enum.at(fields, 2)["text"] == "*Device:*\ndev_1"
      assert Enum.at(fields, 3)["text"] == "*Path:*\ncpu/usage"
    end

    test "device field shows 'all' when device_id is nil" do
      event = %{@event | device_id: nil}
      payload = Notifier.format_slack_payload(event, @rule)
      fields = Enum.at(payload["blocks"], 1)["fields"]

      assert Enum.at(fields, 2)["text"] == "*Device:*\nall"
    end

    test "message block contains event message" do
      payload = Notifier.format_slack_payload(@event, @rule)
      message_block = Enum.at(payload["blocks"], 2)
      assert message_block["text"]["text"] == "CPU at 95%"
    end
  end

  describe "format_email/3" do
    test "builds Swoosh email with correct subject" do
      config = %{"to" => ["ops@example.com"], "from" => {"Alerts", "alerts@example.com"}}
      email = Notifier.format_email(@event, @rule, config)

      assert email.subject == "[CRITICAL] High CPU"
    end

    test "sets to recipients from channel config" do
      config = %{"to" => ["ops@example.com", "oncall@example.com"]}
      email = Notifier.format_email(@event, @rule, config)

      # Swoosh normalizes plain strings to {"", email} tuples
      assert email.to == [{"", "ops@example.com"}, {"", "oncall@example.com"}]
    end

    test "sets from address from channel config" do
      config = %{"to" => ["ops@example.com"], "from" => {"Alerts", "alerts@example.com"}}
      email = Notifier.format_email(@event, @rule, config)

      assert email.from == {"Alerts", "alerts@example.com"}
    end

    test "uses default from when not in config" do
      config = %{"to" => ["ops@example.com"]}
      email = Notifier.format_email(@event, @rule, config)

      assert email.from == {"Switch Telemetry", "alerts@switchtelemetry.local"}
    end

    test "uses empty to list when not in config" do
      config = %{}
      email = Notifier.format_email(@event, @rule, config)

      assert email.to == []
    end

    test "sets text body to event message" do
      config = %{"to" => ["ops@example.com"]}
      email = Notifier.format_email(@event, @rule, config)

      assert email.text_body == "CPU at 95%"
    end

    test "subject reflects severity level" do
      config = %{"to" => []}
      rule = %{@rule | severity: :warning}
      email = Notifier.format_email(@event, rule, config)

      assert email.subject == "[WARNING] High CPU"
    end
  end
end

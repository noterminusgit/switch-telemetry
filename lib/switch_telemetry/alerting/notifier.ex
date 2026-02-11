defmodule SwitchTelemetry.Alerting.Notifier do
  @moduledoc """
  Formats notification payloads for different delivery channels.

  Each format function takes an alert event and its associated rule,
  producing channel-specific payloads (webhook JSON, Slack Block Kit, Swoosh email).
  """

  @doc """
  Formats a generic webhook JSON payload.
  """
  def format_webhook_payload(event, rule) do
    %{
      "alert_rule" => rule.name,
      "severity" => to_string(rule.severity),
      "status" => to_string(event.status),
      "device_id" => event.device_id,
      "path" => rule.path,
      "value" => event.value,
      "message" => event.message,
      "fired_at" => DateTime.to_iso8601(event.inserted_at)
    }
  end

  @doc """
  Formats a Slack Block Kit payload for posting to a Slack webhook URL.
  """
  def format_slack_payload(event, rule) do
    %{
      "blocks" => [
        %{
          "type" => "header",
          "text" => %{"type" => "plain_text", "text" => slack_title(event, rule)}
        },
        %{
          "type" => "section",
          "fields" => [
            %{"type" => "mrkdwn", "text" => "*Severity:*\n#{rule.severity}"},
            %{"type" => "mrkdwn", "text" => "*Status:*\n#{event.status}"},
            %{"type" => "mrkdwn", "text" => "*Device:*\n#{event.device_id || "all"}"},
            %{"type" => "mrkdwn", "text" => "*Path:*\n#{rule.path}"}
          ]
        },
        %{
          "type" => "section",
          "text" => %{"type" => "mrkdwn", "text" => event.message}
        }
      ]
    }
  end

  @doc """
  Formats a Swoosh email struct for delivery via the application mailer.
  """
  def format_email(event, rule, channel_config) do
    Swoosh.Email.new()
    |> Swoosh.Email.to(channel_config["to"] || [])
    |> Swoosh.Email.from(
      channel_config["from"] || {"Switch Telemetry", "alerts@switchtelemetry.local"}
    )
    |> Swoosh.Email.subject("[#{rule.severity |> to_string() |> String.upcase()}] #{rule.name}")
    |> Swoosh.Email.text_body(event.message)
  end

  defp slack_title(_event, rule) do
    emoji =
      case rule.severity do
        :critical -> ":red_circle:"
        :warning -> ":large_orange_circle:"
        :info -> ":large_blue_circle:"
        _ -> ":large_blue_circle:"
      end

    "#{emoji} Alert: #{rule.name}"
  end
end

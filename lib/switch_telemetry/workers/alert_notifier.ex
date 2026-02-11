defmodule SwitchTelemetry.Workers.AlertNotifier do
  @moduledoc """
  Oban worker that delivers alert notifications through configured channels.

  Each job carries an alert_event_id and channel_id. The worker loads both
  records, formats the payload for the channel type, and dispatches the
  notification via Finch (webhook/slack) or Swoosh (email).
  """
  use Oban.Worker, queue: :notifications, max_attempts: 5

  require Logger

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Alerting.{AlertEvent, NotificationChannel}
  alias SwitchTelemetry.Alerting.Notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_event_id" => event_id, "channel_id" => channel_id}}) do
    event = Repo.get!(AlertEvent, event_id) |> Repo.preload(:alert_rule)
    channel = Repo.get!(NotificationChannel, channel_id)
    rule = event.alert_rule

    case channel.type do
      :webhook -> send_webhook(event, rule, channel)
      :slack -> send_slack(event, rule, channel)
      :email -> send_email(event, rule, channel)
    end
  end

  defp send_webhook(event, rule, channel) do
    payload = Notifier.format_webhook_payload(event, rule)
    post_json(channel.config["url"], payload)
  end

  defp send_slack(event, rule, channel) do
    payload = Notifier.format_slack_payload(event, rule)
    post_json(channel.config["url"], payload)
  end

  defp send_email(event, rule, channel) do
    email = Notifier.format_email(event, rule, channel.config)

    case SwitchTelemetry.Mailer.deliver(email) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Email delivery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp post_json(url, payload) do
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)
    req = Finch.build(:post, url, headers, body)

    case Finch.request(req, SwitchTelemetry.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("Notification POST failed with status #{status}: #{body}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Notification POST error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

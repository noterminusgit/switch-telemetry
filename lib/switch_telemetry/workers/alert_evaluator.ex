defmodule SwitchTelemetry.Workers.AlertEvaluator do
  @moduledoc """
  Oban worker that periodically evaluates all enabled alert rules.

  Runs every minute via the Oban Cron plugin. For each enabled rule,
  fetches recent metrics, evaluates the rule condition
  via `Evaluator.evaluate_rule/2`, persists state transitions, creates
  alert events, and enqueues notification delivery jobs.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 1

  alias SwitchTelemetry.Alerting
  alias SwitchTelemetry.Alerting.Evaluator
  alias SwitchTelemetry.Metrics

  @impl Oban.Worker
  def perform(_job) do
    rules = Alerting.list_enabled_rules()

    Enum.each(rules, fn rule ->
      evaluate_and_update(rule)
    end)

    :ok
  end

  defp evaluate_and_update(rule) do
    metrics = fetch_metrics(rule)

    case Evaluator.evaluate_rule(rule, metrics) do
      {:firing, value, message} ->
        handle_firing(rule, value, message)

      {:resolved, message} ->
        handle_resolved(rule, message)

      :ok ->
        :ok
    end
  end

  defp fetch_metrics(rule) do
    # Query recent metrics for this rule's device and path
    # duration_seconds determines how far back to look
    minutes = max(div(rule.duration_seconds, 60), 1)

    opts = [limit: 100, minutes: minutes]

    if rule.device_id do
      Metrics.get_latest(rule.device_id, opts)
      |> Enum.filter(&(&1.path == rule.path))
    else
      # For rules without a specific device, return empty (device-specific rules only for now)
      []
    end
  end

  defp handle_firing(rule, value, message) do
    now = DateTime.utc_now()

    {:ok, _rule} = Alerting.update_rule_state(rule, :firing, timestamp: now)

    {:ok, event} =
      Alerting.create_event(%{
        alert_rule_id: rule.id,
        device_id: rule.device_id,
        status: :firing,
        value: value,
        message: message,
        metadata: %{threshold: rule.threshold, condition: to_string(rule.condition)}
      })

    enqueue_notifications(rule, event)
    broadcast_alert(event)
  end

  defp handle_resolved(rule, message) do
    now = DateTime.utc_now()

    {:ok, _rule} = Alerting.update_rule_state(rule, :ok, timestamp: now)

    {:ok, event} =
      Alerting.create_event(%{
        alert_rule_id: rule.id,
        device_id: rule.device_id,
        status: :resolved,
        value: nil,
        message: message,
        metadata: %{}
      })

    enqueue_notifications(rule, event)
    broadcast_alert(event)
  end

  defp enqueue_notifications(rule, event) do
    channels = Alerting.list_channels_for_rule(rule.id)

    Enum.each(channels, fn channel ->
      %{"alert_event_id" => event.id, "channel_id" => channel.id}
      |> SwitchTelemetry.Workers.AlertNotifier.new()
      |> Oban.insert()
    end)
  end

  defp broadcast_alert(event) do
    topic = "alerts"
    Phoenix.PubSub.broadcast(SwitchTelemetry.PubSub, topic, {:alert_event, event})

    if event.device_id do
      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "alerts:#{event.device_id}",
        {:alert_event, event}
      )
    end
  end
end

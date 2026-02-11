defmodule SwitchTelemetry.Workers.AlertEventPrunerTest do
  use SwitchTelemetry.DataCase, async: true
  use Oban.Testing, repo: SwitchTelemetry.Repo

  alias SwitchTelemetry.Workers.AlertEventPruner
  alias SwitchTelemetry.Alerting

  test "returns ok with no events to prune" do
    assert {:ok, %{deleted: 0}} = perform_job(AlertEventPruner, %{})
  end

  test "prunes events older than 30 days" do
    # Set min_keep to 1 so the old event isn't protected
    Application.put_env(:switch_telemetry, :alert_event_min_keep_per_rule, 1)
    on_exit(fn -> Application.delete_env(:switch_telemetry, :alert_event_min_keep_per_rule) end)

    {:ok, rule} = create_test_rule()
    old_time = DateTime.utc_now() |> DateTime.add(-31 * 86400, :second)

    # Create an old event
    {:ok, _old_event} =
      Alerting.create_event(%{
        alert_rule_id: rule.id,
        status: :firing,
        value: 95.0,
        message: "old alert",
        inserted_at: old_time
      })

    # Create a recent event
    {:ok, _new_event} =
      Alerting.create_event(%{
        alert_rule_id: rule.id,
        status: :resolved,
        value: nil,
        message: "recent alert"
      })

    {:ok, result} = perform_job(AlertEventPruner, %{})
    assert result.deleted >= 1

    # Verify recent event still exists
    events = Alerting.list_events(rule.id)
    assert length(events) >= 1

    # Verify only the recent event remains (old one was pruned)
    assert Enum.all?(events, fn e -> e.status == :resolved end)
  end

  defp create_test_rule do
    Alerting.create_alert_rule(%{
      name: "pruner-test-#{System.unique_integer([:positive])}",
      path: "test/path",
      condition: :above,
      threshold: 90.0,
      duration_seconds: 60,
      cooldown_seconds: 300,
      severity: :warning
    })
  end
end

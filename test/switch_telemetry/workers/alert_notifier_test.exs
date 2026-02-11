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
end

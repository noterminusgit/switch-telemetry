defmodule SwitchTelemetry.Workers.AlertEventPruner do
  @moduledoc """
  Oban cron worker that prunes old alert events.
  Runs daily. Deletes events older than 30 days,
  keeping at least the last 100 events per rule.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  import Ecto.Query
  alias SwitchTelemetry.Repo

  @default_max_age_days 30
  @default_min_keep_per_rule 100

  @impl Oban.Worker
  def perform(_job) do
    max_age_days =
      Application.get_env(:switch_telemetry, :alert_event_max_age_days, @default_max_age_days)

    min_keep =
      Application.get_env(
        :switch_telemetry,
        :alert_event_min_keep_per_rule,
        @default_min_keep_per_rule
      )

    cutoff = DateTime.utc_now() |> DateTime.add(-max_age_days * 86400, :second)

    # Get IDs of events to keep (latest N per rule)
    keep_ids_query =
      from(e in "alert_events",
        select: %{
          id: e.id,
          row_num:
            over(row_number(),
              partition_by: e.alert_rule_id,
              order_by: [desc: e.inserted_at]
            )
        }
      )

    # Delete old events not in the keep set
    {deleted, _} =
      from(e in "alert_events",
        where: e.inserted_at < ^cutoff,
        where:
          e.id not in subquery(
            from(k in subquery(keep_ids_query),
              where: k.row_num <= ^min_keep,
              select: k.id
            )
          )
      )
      |> Repo.delete_all()

    {:ok, %{deleted: deleted}}
  end
end

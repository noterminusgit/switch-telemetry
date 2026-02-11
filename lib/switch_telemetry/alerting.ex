defmodule SwitchTelemetry.Alerting do
  @moduledoc """
  Context for managing alert rules, notification channels, bindings, and events.
  """
  import Ecto.Query

  alias SwitchTelemetry.Repo

  alias SwitchTelemetry.Alerting.{
    AlertRule,
    AlertEvent,
    AlertChannelBinding,
    NotificationChannel
  }

  # --- AlertRule CRUD ---

  def list_alert_rules do
    Repo.all(AlertRule)
  end

  def list_enabled_rules do
    from(r in AlertRule, where: r.enabled == true)
    |> Repo.all()
  end

  def get_alert_rule!(id), do: Repo.get!(AlertRule, id)

  def get_alert_rule(id), do: Repo.get(AlertRule, id)

  def create_alert_rule(attrs) do
    attrs = maybe_put_id(attrs)

    %AlertRule{}
    |> AlertRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_alert_rule(%AlertRule{} = rule, attrs) do
    rule
    |> AlertRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_alert_rule(%AlertRule{} = rule) do
    Repo.delete(rule)
  end

  # --- NotificationChannel CRUD ---

  def list_channels do
    Repo.all(NotificationChannel)
  end

  def get_channel!(id), do: Repo.get!(NotificationChannel, id)

  def create_channel(attrs) do
    attrs = maybe_put_id(attrs)

    %NotificationChannel{}
    |> NotificationChannel.changeset(attrs)
    |> Repo.insert()
  end

  def update_channel(%NotificationChannel{} = channel, attrs) do
    channel
    |> NotificationChannel.changeset(attrs)
    |> Repo.update()
  end

  def delete_channel(%NotificationChannel{} = channel) do
    Repo.delete(channel)
  end

  # --- AlertChannelBinding ---

  def bind_channel(rule_id, channel_id) do
    now = DateTime.utc_now()

    attrs = %{
      id: generate_id(),
      alert_rule_id: rule_id,
      notification_channel_id: channel_id
    }

    %AlertChannelBinding{}
    |> AlertChannelBinding.changeset(attrs)
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Repo.insert()
  end

  def unbind_channel(rule_id, channel_id) do
    query =
      from(b in AlertChannelBinding,
        where: b.alert_rule_id == ^rule_id and b.notification_channel_id == ^channel_id
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      binding -> Repo.delete(binding)
    end
  end

  def list_channels_for_rule(rule_id) do
    from(nc in NotificationChannel,
      join: b in AlertChannelBinding,
      on: b.notification_channel_id == nc.id,
      where: b.alert_rule_id == ^rule_id
    )
    |> Repo.all()
  end

  # --- AlertEvent ---

  def create_event(attrs) do
    attrs =
      attrs
      |> maybe_put_id()
      |> maybe_put_inserted_at()

    %AlertEvent{}
    |> Ecto.Changeset.cast(attrs, [:id, :alert_rule_id, :device_id, :status, :value, :message, :metadata, :inserted_at])
    |> Ecto.Changeset.validate_required([:id, :alert_rule_id, :status, :inserted_at])
    |> Repo.insert()
  end

  def list_events(rule_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(e in AlertEvent,
      where: e.alert_rule_id == ^rule_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_recent_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(e in AlertEvent,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  # --- State Management ---

  def update_rule_state(%AlertRule{} = rule, new_state, opts \\ []) do
    now = Keyword.get(opts, :timestamp, DateTime.utc_now())

    state_attrs = %{state: new_state}

    state_attrs =
      case new_state do
        :firing -> Map.put(state_attrs, :last_fired_at, now)
        :ok -> Map.put(state_attrs, :last_resolved_at, now)
        _ -> state_attrs
      end

    rule
    |> AlertRule.changeset(state_attrs)
    |> Repo.update()
  end

  # --- Helpers ---

  defp generate_id do
    Ecto.UUID.generate()
  end

  defp maybe_put_id(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :id) and attrs.id != nil -> attrs
      Map.has_key?(attrs, "id") and attrs["id"] != nil -> attrs
      true -> Map.put(attrs, :id, generate_id())
    end
  end

  defp maybe_put_inserted_at(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :inserted_at) and attrs.inserted_at != nil -> attrs
      Map.has_key?(attrs, "inserted_at") and attrs["inserted_at"] != nil -> attrs
      true -> Map.put(attrs, :inserted_at, DateTime.utc_now())
    end
  end
end

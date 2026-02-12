defmodule SwitchTelemetry.AlertingTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Alerting

  # --- Helpers ---

  defp valid_rule_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Rule #{System.unique_integer([:positive])}",
        path: "/interfaces/interface/state/counters/in-octets",
        condition: :above,
        threshold: 90.0,
        duration_seconds: 120,
        severity: :critical
      },
      overrides
    )
  end

  defp valid_channel_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Channel #{System.unique_integer([:positive])}",
        type: :webhook,
        config: %{"url" => "https://hooks.example.com/alert"}
      },
      overrides
    )
  end

  defp create_rule(overrides \\ %{}) do
    {:ok, rule} = Alerting.create_alert_rule(valid_rule_attrs(overrides))
    rule
  end

  defp create_channel(overrides \\ %{}) do
    {:ok, channel} = Alerting.create_channel(valid_channel_attrs(overrides))
    channel
  end

  # --- AlertRule CRUD ---

  describe "create_alert_rule/1" do
    test "with valid attrs creates an alert rule" do
      assert {:ok, rule} = Alerting.create_alert_rule(valid_rule_attrs())
      assert rule.name =~ "Rule"
      assert rule.condition == :above
      assert rule.threshold == 90.0
      assert rule.id != nil
    end

    test "with invalid attrs returns error changeset" do
      assert {:error, changeset} = Alerting.create_alert_rule(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "with duplicate name returns error" do
      attrs = valid_rule_attrs(%{name: "Unique Rule Name"})
      assert {:ok, _rule} = Alerting.create_alert_rule(attrs)

      assert {:error, changeset} =
               Alerting.create_alert_rule(valid_rule_attrs(%{name: "Unique Rule Name"}))

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_alert_rules/0" do
    test "returns all alert rules" do
      rule1 = create_rule()
      rule2 = create_rule()
      rules = Alerting.list_alert_rules()
      rule_ids = Enum.map(rules, & &1.id)
      assert rule1.id in rule_ids
      assert rule2.id in rule_ids
    end
  end

  describe "list_enabled_rules/0" do
    test "returns only enabled rules" do
      enabled_rule = create_rule(%{enabled: true})
      _disabled_rule = create_rule(%{enabled: false})

      rules = Alerting.list_enabled_rules()
      rule_ids = Enum.map(rules, & &1.id)
      assert enabled_rule.id in rule_ids
    end

    test "excludes disabled rules" do
      _enabled_rule = create_rule(%{enabled: true})
      disabled_rule = create_rule(%{enabled: false})

      rules = Alerting.list_enabled_rules()
      rule_ids = Enum.map(rules, & &1.id)
      refute disabled_rule.id in rule_ids
    end
  end

  describe "get_alert_rule!/1" do
    test "returns the rule with given id" do
      rule = create_rule()
      fetched = Alerting.get_alert_rule!(rule.id)
      assert fetched.id == rule.id
      assert fetched.name == rule.name
    end

    test "raises when rule not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Alerting.get_alert_rule!("nonexistent_id")
      end
    end
  end

  describe "update_alert_rule/2" do
    test "updates the rule with valid attrs" do
      rule = create_rule()
      assert {:ok, updated} = Alerting.update_alert_rule(rule, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
      assert updated.id == rule.id
    end

    test "returns error with invalid attrs" do
      rule = create_rule()
      assert {:error, changeset} = Alerting.update_alert_rule(rule, %{name: nil})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_alert_rule/1" do
    test "deletes the rule" do
      rule = create_rule()
      assert {:ok, _deleted} = Alerting.delete_alert_rule(rule)
      assert Alerting.get_alert_rule(rule.id) == nil
    end
  end

  # --- NotificationChannel CRUD ---

  describe "create_channel/1" do
    test "with valid attrs creates a channel" do
      assert {:ok, channel} = Alerting.create_channel(valid_channel_attrs())
      assert channel.name =~ "Channel"
      assert channel.type == :webhook
      assert channel.id != nil
    end

    test "with invalid attrs returns error changeset" do
      assert {:error, changeset} = Alerting.create_channel(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_channels/0" do
    test "returns all channels" do
      channel1 = create_channel()
      channel2 = create_channel()
      channels = Alerting.list_channels()
      channel_ids = Enum.map(channels, & &1.id)
      assert channel1.id in channel_ids
      assert channel2.id in channel_ids
    end
  end

  describe "update_channel/2" do
    test "updates the channel with valid attrs" do
      channel = create_channel()
      assert {:ok, updated} = Alerting.update_channel(channel, %{name: "Updated Channel"})
      assert updated.name == "Updated Channel"
    end
  end

  describe "delete_channel/1" do
    test "deletes the channel" do
      channel = create_channel()
      assert {:ok, _deleted} = Alerting.delete_channel(channel)

      assert_raise Ecto.NoResultsError, fn ->
        Alerting.get_channel!(channel.id)
      end
    end
  end

  # --- AlertChannelBinding ---

  describe "bind_channel/2" do
    test "binds a channel to a rule" do
      rule = create_rule()
      channel = create_channel()
      assert {:ok, binding} = Alerting.bind_channel(rule.id, channel.id)
      assert binding.alert_rule_id == rule.id
      assert binding.notification_channel_id == channel.id
    end

    test "duplicate binding returns error" do
      rule = create_rule()
      channel = create_channel()
      assert {:ok, _binding} = Alerting.bind_channel(rule.id, channel.id)
      assert {:error, _changeset} = Alerting.bind_channel(rule.id, channel.id)
    end
  end

  describe "unbind_channel/2" do
    test "removes binding between rule and channel" do
      rule = create_rule()
      channel = create_channel()
      {:ok, _binding} = Alerting.bind_channel(rule.id, channel.id)

      assert {:ok, _deleted} = Alerting.unbind_channel(rule.id, channel.id)
      assert Alerting.list_channels_for_rule(rule.id) == []
    end

    test "returns error when binding not found" do
      assert {:error, :not_found} = Alerting.unbind_channel("no_rule", "no_channel")
    end
  end

  describe "list_channels_for_rule/1" do
    test "returns channels bound to a rule" do
      rule = create_rule()
      channel1 = create_channel()
      channel2 = create_channel()
      unbound_channel = create_channel()

      {:ok, _} = Alerting.bind_channel(rule.id, channel1.id)
      {:ok, _} = Alerting.bind_channel(rule.id, channel2.id)

      channels = Alerting.list_channels_for_rule(rule.id)
      channel_ids = Enum.map(channels, & &1.id)
      assert channel1.id in channel_ids
      assert channel2.id in channel_ids
      refute unbound_channel.id in channel_ids
    end

    test "returns empty list when no channels bound" do
      rule = create_rule()
      assert Alerting.list_channels_for_rule(rule.id) == []
    end
  end

  # --- AlertEvent ---

  describe "create_event/1" do
    test "creates an event with valid attrs" do
      rule = create_rule()

      assert {:ok, event} =
               Alerting.create_event(%{
                 alert_rule_id: rule.id,
                 status: :firing,
                 value: 95.5,
                 message: "CPU above threshold"
               })

      assert event.alert_rule_id == rule.id
      assert event.status == :firing
      assert event.value == 95.5
      assert event.id != nil
      assert event.inserted_at != nil
    end
  end

  describe "list_events/1" do
    test "returns events for a specific rule" do
      rule1 = create_rule()
      rule2 = create_rule()

      {:ok, event1} =
        Alerting.create_event(%{alert_rule_id: rule1.id, status: :firing, value: 95.0})

      {:ok, _event2} =
        Alerting.create_event(%{alert_rule_id: rule2.id, status: :firing, value: 80.0})

      events = Alerting.list_events(rule1.id)
      assert length(events) == 1
      assert hd(events).id == event1.id
    end

    test "respects limit option" do
      rule = create_rule()

      for i <- 1..5 do
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :firing,
          value: 90.0 + i,
          inserted_at: DateTime.add(DateTime.utc_now(), i, :second)
        })
      end

      events = Alerting.list_events(rule.id, limit: 3)
      assert length(events) == 3
    end

    test "orders by inserted_at descending" do
      rule = create_rule()
      now = DateTime.utc_now()

      {:ok, _old} =
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :firing,
          value: 90.0,
          inserted_at: DateTime.add(now, -60, :second)
        })

      {:ok, new} =
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :resolved,
          value: 50.0,
          inserted_at: DateTime.add(now, 60, :second)
        })

      events = Alerting.list_events(rule.id)
      assert hd(events).id == new.id
    end
  end

  describe "list_recent_events/1" do
    test "returns events across all rules" do
      rule1 = create_rule()
      rule2 = create_rule()

      {:ok, _} = Alerting.create_event(%{alert_rule_id: rule1.id, status: :firing, value: 95.0})
      {:ok, _} = Alerting.create_event(%{alert_rule_id: rule2.id, status: :firing, value: 80.0})

      events = Alerting.list_recent_events(limit: 10)
      rule_ids = Enum.map(events, & &1.alert_rule_id)
      assert rule1.id in rule_ids
      assert rule2.id in rule_ids
    end

    test "respects limit option" do
      rule = create_rule()

      for i <- 1..5 do
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :firing,
          value: 90.0 + i,
          inserted_at: DateTime.add(DateTime.utc_now(), i, :second)
        })
      end

      events = Alerting.list_recent_events(limit: 2)
      assert length(events) == 2
    end
  end

  # --- State Management ---

  describe "update_rule_state/3" do
    test "transitioning to :firing sets last_fired_at" do
      rule = create_rule()
      assert rule.state == :ok

      assert {:ok, updated} = Alerting.update_rule_state(rule, :firing)
      assert updated.state == :firing
      assert updated.last_fired_at != nil
    end

    test "transitioning to :ok sets last_resolved_at" do
      rule = create_rule()
      {:ok, firing_rule} = Alerting.update_rule_state(rule, :firing)

      assert {:ok, resolved} = Alerting.update_rule_state(firing_rule, :ok)
      assert resolved.state == :ok
      assert resolved.last_resolved_at != nil
    end

    test "transitioning to :acknowledged does not set timestamps" do
      rule = create_rule()
      {:ok, firing_rule} = Alerting.update_rule_state(rule, :firing)

      assert {:ok, acked} = Alerting.update_rule_state(firing_rule, :acknowledged)
      assert acked.state == :acknowledged
      # last_fired_at was set during the firing transition, not during acknowledged
      assert acked.last_fired_at == firing_rule.last_fired_at
    end

    test "accepts a custom timestamp" do
      rule = create_rule()
      custom_time = ~U[2025-01-15 12:00:00.000000Z]

      assert {:ok, updated} = Alerting.update_rule_state(rule, :firing, timestamp: custom_time)
      assert updated.last_fired_at == custom_time
    end
  end
end

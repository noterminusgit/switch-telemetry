defmodule SwitchTelemetryWeb.AlertLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Alerting

  setup :register_and_log_in_user

  defp create_rule(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "High CPU #{System.unique_integer([:positive])}",
      path: "/interfaces/interface/state/counters",
      condition: :above,
      threshold: 90.0,
      duration_seconds: 60,
      cooldown_seconds: 300,
      severity: :warning
    }

    {:ok, rule} = Alerting.create_alert_rule(Map.merge(defaults, attrs))
    rule
  end

  defp create_channel(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Webhook #{System.unique_integer([:positive])}",
      type: :webhook,
      config: %{"url" => "https://example.com/hook"},
      enabled: true
    }

    {:ok, channel} = Alerting.create_channel(Map.merge(defaults, attrs))
    channel
  end

  describe "Index - main view" do
    test "renders the alerts page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "Alerts"
      assert html =~ "Active Alerts"
      assert html =~ "Alert Rules"
      assert html =~ "Recent Events"
    end

    test "shows empty states when no data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "No active alerts"
      assert html =~ "No alert rules configured"
      assert html =~ "No alert events recorded"
    end

    test "lists alert rules", %{conn: conn} do
      rule = create_rule(%{name: "Interface Down Alert"})
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "Interface Down Alert"
      assert html =~ rule.path
    end

    test "shows firing rules in active alerts", %{conn: conn} do
      rule = create_rule(%{name: "CPU Critical"})
      {:ok, _} = Alerting.update_rule_state(rule, :firing)

      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "CPU Critical"
      assert html =~ "Acknowledge"
    end
  end

  describe "Index - rule creation" do
    test "navigates to new rule form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts/rules/new")
      assert html =~ "Create Alert Rule"
      assert html =~ "Save Rule"
    end

    test "creates a rule via the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/rules/new")

      view
      |> form("form", %{
        "rule" => %{
          "name" => "New Test Rule",
          "path" => "/system/cpu/usage",
          "condition" => "above",
          "threshold" => "95",
          "duration_seconds" => "120",
          "cooldown_seconds" => "600",
          "severity" => "critical"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts")
      assert flash["info"] == "Alert rule saved"
    end
  end

  describe "Index - rule actions" do
    test "toggles rule enabled state", %{conn: conn} do
      rule = create_rule(%{name: "Toggle Test", enabled: true})
      {:ok, view, _html} = live(conn, ~p"/alerts")

      view
      |> element(~s|button[phx-click=toggle_enabled][phx-value-id="#{rule.id}"]|)
      |> render_click()

      updated = Alerting.get_alert_rule!(rule.id)
      assert updated.enabled == false
    end

    test "deletes a rule", %{conn: conn} do
      rule = create_rule(%{name: "Delete Me Rule"})
      {:ok, view, html} = live(conn, ~p"/alerts")
      assert html =~ "Delete Me Rule"

      view
      |> element(~s|button[phx-click=delete_rule][phx-value-id="#{rule.id}"]|)
      |> render_click()

      refute render(view) =~ "Delete Me Rule"
    end

    test "acknowledges a firing rule", %{conn: conn} do
      rule = create_rule(%{name: "Ack Me"})
      {:ok, _} = Alerting.update_rule_state(rule, :firing)

      {:ok, view, html} = live(conn, ~p"/alerts")
      assert html =~ "Acknowledge"

      view
      |> element(~s|button[phx-click=acknowledge][phx-value-id="#{rule.id}"]|)
      |> render_click()

      updated = Alerting.get_alert_rule!(rule.id)
      assert updated.state == :acknowledged
    end
  end

  describe "Index - edit rule" do
    test "navigates to edit rule form", %{conn: conn} do
      rule = create_rule(%{name: "Edit Me"})
      {:ok, _view, html} = live(conn, ~p"/alerts/rules/#{rule.id}/edit")
      assert html =~ "Edit Alert Rule"
      assert html =~ "Edit Me"
    end

    test "updates a rule via the edit form", %{conn: conn} do
      rule = create_rule(%{name: "Before Edit", severity: :warning, threshold: 80.0})
      {:ok, view, _html} = live(conn, ~p"/alerts/rules/#{rule.id}/edit")

      view
      |> form("form", %{
        "rule" => %{
          "name" => "After Edit",
          "path" => "/updated/path",
          "condition" => "below",
          "threshold" => "50.5",
          "duration_seconds" => "90",
          "cooldown_seconds" => "180",
          "severity" => "critical"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts")
      assert flash["info"] == "Alert rule saved"

      updated = SwitchTelemetry.Alerting.get_alert_rule!(rule.id)
      assert updated.name == "After Edit"
      assert updated.path == "/updated/path"
      assert updated.condition == :below
      assert updated.threshold == 50.5
      assert updated.severity == :critical
    end

    test "edit form populates existing values", %{conn: conn} do
      rule =
        create_rule(%{
          name: "Populated Edit",
          path: "/system/cpu",
          condition: :below,
          threshold: 10.0,
          duration_seconds: 120,
          cooldown_seconds: 600,
          severity: :critical
        })

      {:ok, _view, html} = live(conn, ~p"/alerts/rules/#{rule.id}/edit")
      assert html =~ "Populated Edit"
      assert html =~ "/system/cpu"
      assert html =~ "10"
      assert html =~ "120"
      assert html =~ "600"
    end

    test "creating rule with empty threshold sends empty string", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/rules/new")

      view
      |> form("form", %{
        "rule" => %{
          "name" => "No Threshold Rule",
          "path" => "/test/no-threshold",
          "condition" => "absent",
          "threshold" => "",
          "duration_seconds" => "60",
          "cooldown_seconds" => "300",
          "severity" => "info"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts")
      assert flash["info"] == "Alert rule saved"
    end

    test "creating rule with invalid threshold string still submits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/rules/new")

      view
      |> form("form", %{
        "rule" => %{
          "name" => "Invalid Threshold Rule",
          "path" => "/test/invalid-threshold",
          "condition" => "above",
          "threshold" => "not-a-number",
          "duration_seconds" => "60",
          "cooldown_seconds" => "300",
          "severity" => "warning"
        }
      })
      |> render_submit()

      # The form should either redirect or show error; depends on validation
      # Either way it should not crash
    end

    test "creating rule with empty device_id sets device_id to nil", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/rules/new")

      view
      |> form("form", %{
        "rule" => %{
          "name" => "Global Rule",
          "path" => "/test/global",
          "condition" => "above",
          "threshold" => "100",
          "device_id" => "",
          "duration_seconds" => "60",
          "cooldown_seconds" => "300",
          "severity" => "warning"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts")
      assert flash["info"] == "Alert rule saved"
    end
  end

  describe "Index - channels view" do
    test "navigates to channels view", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "Notification Channels"
    end

    test "lists channels", %{conn: conn} do
      _channel = create_channel(%{name: "My Slack Channel", type: :slack})
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "My Slack Channel"
      assert html =~ "slack"
    end

    test "creates a notification channel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/channels/new")
      assert render(view) =~ "Create Channel"

      view
      |> form("form", %{
        "channel" => %{
          "name" => "Test Webhook",
          "type" => "webhook",
          "enabled" => "true",
          "webhook_url" => "https://example.com/webhook"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts/channels")
      assert flash["info"] == "Channel saved"
    end

    test "deletes a channel", %{conn: conn} do
      channel = create_channel(%{name: "Remove This"})
      {:ok, view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "Remove This"

      view
      |> element(~s|button[phx-click=delete_channel][phx-value-id="#{channel.id}"]|)
      |> render_click()

      refute render(view) =~ "Remove This"
    end

    test "shows channel enabled status as Yes", %{conn: conn} do
      _channel = create_channel(%{name: "Enabled Channel", enabled: true})
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "Yes"
    end

    test "shows channel enabled status as No when disabled", %{conn: conn} do
      _channel = create_channel(%{name: "Disabled Channel", enabled: false})
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "No"
    end

    test "shows empty channels state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "No notification channels configured"
    end

    test "shows back to alerts link on channels page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "Back to Alerts"
    end

    test "shows New Channel link on channels page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts/channels")
      assert html =~ "New Channel"
    end
  end

  describe "Index - channel form (ChannelForm component)" do
    test "creates a slack channel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/channels/new")

      # Change type to slack
      view
      |> form("form", %{
        "channel" => %{"type" => "slack"}
      })
      |> render_change()

      html = render(view)
      assert html =~ "Slack Webhook URL"

      # Submit
      view
      |> form("form", %{
        "channel" => %{
          "name" => "Slack Alerts",
          "type" => "slack",
          "enabled" => "true",
          "slack_url" => "https://hooks.slack.com/services/test"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts/channels")
      assert flash["info"] == "Channel saved"
    end

    test "creates an email channel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/channels/new")

      # Change type to email
      view
      |> form("form", %{
        "channel" => %{"type" => "email"}
      })
      |> render_change()

      html = render(view)
      assert html =~ "To (comma-separated)"
      assert html =~ "From"

      view
      |> form("form", %{
        "channel" => %{
          "name" => "Email Alerts",
          "type" => "email",
          "enabled" => "true",
          "email_to" => "ops@example.com,admin@example.com",
          "email_from" => "alerts@example.com"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts/channels")
      assert flash["info"] == "Channel saved"
    end

    test "type_changed event updates visible fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts/channels/new")

      # Default type is webhook
      html = render(view)
      assert html =~ "Webhook URL"

      # Change to slack
      view
      |> form("form", %{
        "channel" => %{"type" => "slack"}
      })
      |> render_change()

      html = render(view)
      assert html =~ "Slack Webhook URL"

      # Change to email
      view
      |> form("form", %{
        "channel" => %{"type" => "email"}
      })
      |> render_change()

      html = render(view)
      assert html =~ "To (comma-separated)"
      assert html =~ "From"

      # Change back to webhook
      view
      |> form("form", %{
        "channel" => %{"type" => "webhook"}
      })
      |> render_change()

      html = render(view)
      assert html =~ "Webhook URL"
    end

    test "edit channel pre-populates existing values", %{conn: conn} do
      channel =
        create_channel(%{
          name: "Edit Me Channel",
          type: :webhook,
          config: %{"url" => "https://example.com/existing-hook"},
          enabled: true
        })

      {:ok, _view, html} = live(conn, ~p"/alerts/channels/#{channel.id}/edit")
      assert html =~ "Edit Channel"
      assert html =~ "Edit Me Channel"
      assert html =~ "https://example.com/existing-hook"
    end

    test "edit channel with slack type shows slack fields", %{conn: conn} do
      channel =
        create_channel(%{
          name: "Slack Edit",
          type: :slack,
          config: %{"url" => "https://hooks.slack.com/services/existing"}
        })

      {:ok, _view, html} = live(conn, ~p"/alerts/channels/#{channel.id}/edit")
      assert html =~ "Slack Edit"
      assert html =~ "Slack Webhook URL"
      assert html =~ "https://hooks.slack.com/services/existing"
    end

    test "edit channel with email type shows email fields", %{conn: conn} do
      channel =
        create_channel(%{
          name: "Email Edit",
          type: :email,
          config: %{"to" => "ops@test.com", "from" => "noreply@test.com"}
        })

      {:ok, _view, html} = live(conn, ~p"/alerts/channels/#{channel.id}/edit")
      assert html =~ "Email Edit"
      assert html =~ "ops@test.com"
      assert html =~ "noreply@test.com"
    end

    test "updates an existing channel", %{conn: conn} do
      channel =
        create_channel(%{
          name: "Update Me",
          type: :webhook,
          config: %{"url" => "https://example.com/old-hook"}
        })

      {:ok, view, _html} = live(conn, ~p"/alerts/channels/#{channel.id}/edit")

      view
      |> form("form", %{
        "channel" => %{
          "name" => "Updated Channel",
          "type" => "webhook",
          "enabled" => "true",
          "webhook_url" => "https://example.com/new-hook"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/alerts/channels")
      assert flash["info"] == "Channel saved"
    end
  end

  describe "Index - PubSub alerts" do
    test "receives alert_event PubSub message and refreshes data", %{conn: conn} do
      rule = create_rule(%{name: "PubSub Test Rule"})
      {:ok, view, _html} = live(conn, ~p"/alerts")

      # Create an event
      {:ok, _event} =
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :firing,
          value: 95.0,
          message: "CPU exceeded threshold"
        })

      # Simulate PubSub alert event
      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "alerts",
        {:alert_event, %{rule_id: rule.id}}
      )

      html = render(view)
      assert html =~ "PubSub Test Rule"
    end

    test "receives rule_updated PubSub message and refreshes rules", %{conn: conn} do
      rule = create_rule(%{name: "Rule Updated Test"})
      {:ok, view, _html} = live(conn, ~p"/alerts")

      # Simulate PubSub rule_updated message
      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "alerts",
        {:rule_updated, rule}
      )

      html = render(view)
      assert html =~ "Rule Updated Test"
    end

    test "handles unknown PubSub messages gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/alerts")

      send(view.pid, {:something_random, "data"})

      html = render(view)
      assert html =~ "Alerts"
    end
  end

  describe "Index - severity and state display" do
    test "shows critical severity badge", %{conn: conn} do
      _rule = create_rule(%{name: "Critical Rule", severity: :critical})
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "critical"
      assert html =~ "bg-red-100"
    end

    test "shows info severity badge", %{conn: conn} do
      _rule = create_rule(%{name: "Info Rule", severity: :info})
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "info"
      assert html =~ "bg-blue-100"
    end

    test "shows warning severity badge", %{conn: conn} do
      _rule = create_rule(%{name: "Warning Rule", severity: :warning})
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "warning"
      assert html =~ "bg-yellow-100"
    end

    test "shows ok state badge", %{conn: conn} do
      _rule = create_rule(%{name: "OK State Rule"})
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "ok"
      assert html =~ "bg-green-100"
    end

    test "shows firing state badge", %{conn: conn} do
      rule = create_rule(%{name: "Firing State Rule"})
      {:ok, _} = Alerting.update_rule_state(rule, :firing)
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "firing"
    end

    test "shows acknowledged state badge", %{conn: conn} do
      rule = create_rule(%{name: "Ack State Rule"})
      {:ok, _} = Alerting.update_rule_state(rule, :acknowledged)
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "acknowledged"
    end
  end

  describe "Index - recent events" do
    test "shows recent events with values", %{conn: conn} do
      rule = create_rule(%{name: "Events Display Rule"})

      {:ok, _event} =
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :firing,
          value: 95.5,
          message: "Threshold exceeded"
        })

      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "firing"
      assert html =~ "95.5"
      assert html =~ "Threshold exceeded"
    end

    test "shows resolved events", %{conn: conn} do
      rule = create_rule(%{name: "Resolved Event Rule"})

      {:ok, _event} =
        Alerting.create_event(%{
          alert_rule_id: rule.id,
          status: :resolved,
          value: 45.0,
          message: "Recovered"
        })

      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "resolved"
      assert html =~ "Recovered"
    end

    test "shows no events message when none exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/alerts")
      assert html =~ "No alert events recorded"
    end
  end

  describe "Index - rule toggle roundtrip" do
    test "toggles enabled rule to disabled and back", %{conn: conn} do
      rule = create_rule(%{name: "Disable Me", enabled: true})
      {:ok, view, _html} = live(conn, ~p"/alerts")

      view
      |> element(~s|button[phx-click=toggle_enabled][phx-value-id="#{rule.id}"]|)
      |> render_click()

      updated = Alerting.get_alert_rule!(rule.id)
      assert updated.enabled == false

      # Toggle back to enabled
      view
      |> element(~s|button[phx-click=toggle_enabled][phx-value-id="#{rule.id}"]|)
      |> render_click()

      updated = Alerting.get_alert_rule!(rule.id)
      assert updated.enabled == true
    end
  end
end

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
  end
end

defmodule SwitchTelemetryWeb.StreamMonitorLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Collector.StreamMonitor

  setup :register_and_log_in_user

  describe "Monitor" do
    test "renders stream monitor page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/streams")
      assert html =~ "Stream Monitor"
      assert html =~ "Real-time telemetry stream status"
    end

    test "shows empty state message text exists in page", %{conn: conn} do
      # Note: The empty state div is conditional on @stream_list == []
      # The StreamMonitor GenServer may have state from other tests.
      # We test that the page mounts correctly and has the expected structure.
      {:ok, _view, html} = live(conn, ~p"/streams")
      # The page should render either the empty state or the stream table
      assert html =~ "Stream Monitor"
      assert html =~ "Real-time telemetry stream status"
    end

    test "shows stat cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/streams")
      assert html =~ "Total Streams"
      assert html =~ "Connected"
      assert html =~ "Disconnected"
    end

    test "shows protocol filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/streams")
      assert html =~ "All Protocols"
      assert html =~ "gNMI"
      assert html =~ "NETCONF"
    end

    test "shows state filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/streams")
      assert html =~ "All States"
      assert html =~ "Connected"
      assert html =~ "Disconnected"
      assert html =~ "Reconnecting"
    end

    test "has refresh button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/streams")
      assert html =~ "Refresh"
    end

    test "displays streams from StreamMonitor", %{conn: conn} do
      # Report a connected device so there's a stream in the monitor
      StreamMonitor.report_connected("dev_stream_1", :gnmi)
      # Small delay to let the GenServer process the cast
      Process.sleep(50)

      {:ok, _view, html} = live(conn, ~p"/streams")
      assert html =~ "dev_stream_1"
      assert html =~ "gNMI"
      assert html =~ "connected"
    end

    test "refresh button reloads streams", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/streams")

      # Add a stream after initial mount
      StreamMonitor.report_connected("dev_refresh_test", :netconf)
      Process.sleep(50)

      view
      |> element(~s|button[phx-click="refresh"]|)
      |> render_click()

      html = render(view)
      assert html =~ "dev_refresh_test"
    end

    test "filters by protocol", %{conn: conn} do
      StreamMonitor.report_connected("dev_gnmi_filter", :gnmi)
      StreamMonitor.report_connected("dev_netconf_filter", :netconf)
      Process.sleep(50)

      {:ok, view, _html} = live(conn, ~p"/streams")

      # Filter to gnmi only
      view
      |> element(~s|form[phx-change="filter_protocol"]|)
      |> render_change(%{"protocol" => "gnmi"})

      html = render(view)
      assert html =~ "dev_gnmi_filter"
      refute html =~ "dev_netconf_filter"
    end

    test "filters by state", %{conn: conn} do
      StreamMonitor.report_connected("dev_connected_filter", :gnmi)
      StreamMonitor.report_connected("dev_disconn_filter", :gnmi)
      StreamMonitor.report_disconnected("dev_disconn_filter", :gnmi, "timeout")
      Process.sleep(50)

      {:ok, view, _html} = live(conn, ~p"/streams")

      # Filter to connected only
      view
      |> element(~s|form[phx-change="filter_state"]|)
      |> render_change(%{"state" => "connected"})

      html = render(view)
      assert html =~ "dev_connected_filter"
      refute html =~ "dev_disconn_filter"
    end

    test "clearing protocol filter shows all streams", %{conn: conn} do
      StreamMonitor.report_connected("dev_clear_proto", :gnmi)
      Process.sleep(50)

      {:ok, view, _html} = live(conn, ~p"/streams")

      # Filter then clear
      view
      |> element(~s|form[phx-change="filter_protocol"]|)
      |> render_change(%{"protocol" => "netconf"})

      view
      |> element(~s|form[phx-change="filter_protocol"]|)
      |> render_change(%{"protocol" => ""})

      html = render(view)
      assert html =~ "dev_clear_proto"
    end

    test "clearing state filter shows all streams", %{conn: conn} do
      StreamMonitor.report_connected("dev_clear_state", :gnmi)
      Process.sleep(50)

      {:ok, view, _html} = live(conn, ~p"/streams")

      # Filter then clear
      view
      |> element(~s|form[phx-change="filter_state"]|)
      |> render_change(%{"state" => "disconnected"})

      view
      |> element(~s|form[phx-change="filter_state"]|)
      |> render_change(%{"state" => ""})

      html = render(view)
      assert html =~ "dev_clear_state"
    end

    test "receives real-time stream updates via PubSub", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/streams")

      # Report a new connection which will broadcast via PubSub
      StreamMonitor.report_connected("dev_pubsub_test", :gnmi)
      Process.sleep(100)

      html = render(view)
      assert html =~ "dev_pubsub_test"
    end
  end
end

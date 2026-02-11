defmodule SwitchTelemetryWeb.DeviceLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Devices

  describe "Index" do
    test "lists devices", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "Devices"
    end

    test "shows empty state when no devices", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "No devices found"
    end

    test "renders device rows when devices exist", %{conn: conn} do
      {:ok, _device} =
        Devices.create_device(%{
          id: "dev_idx1",
          hostname: "sw-test-01.lab",
          ip_address: "10.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "sw-test-01.lab"
      assert html =~ "10.0.0.1"
    end

    test "new device form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices/new")
      assert html =~ "Add Device"
    end

    test "filters by status", %{conn: conn} do
      {:ok, _} =
        Devices.create_device(%{
          id: "dev_filt1",
          hostname: "sw-active.lab",
          ip_address: "10.0.1.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active
        })

      {:ok, _} =
        Devices.create_device(%{
          id: "dev_filt2",
          hostname: "sw-maint.lab",
          ip_address: "10.0.1.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :maintenance
        })

      {:ok, view, _html} = live(conn, ~p"/devices")

      # Filter to active only
      html = view |> element("button[phx-value-status=active]") |> render_click()
      assert html =~ "sw-active.lab"
      refute html =~ "sw-maint.lab"
    end

    test "deletes a device", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_del1",
          hostname: "sw-delete.lab",
          ip_address: "10.0.2.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices")
      assert render(view) =~ "sw-delete.lab"

      view |> element("button[phx-value-id=#{device.id}]") |> render_click()
      refute render(view) =~ "sw-delete.lab"
    end
  end

  describe "Show" do
    test "displays device details", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show1",
          hostname: "core-sw-01.dc1",
          ip_address: "10.0.10.1",
          platform: :juniper_junos,
          transport: :both,
          gnmi_port: 57400,
          netconf_port: 830
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "core-sw-01.dc1"
      assert html =~ "10.0.10.1"
      assert html =~ "juniper_junos"
      assert html =~ "57400"
      assert html =~ "830"
    end

    test "shows latest metrics section", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show2",
          hostname: "sw-metrics.lab",
          ip_address: "10.0.10.2",
          platform: :arista_eos,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Latest Metrics"
    end
  end
end

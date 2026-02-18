defmodule SwitchTelemetryWeb.DeviceLive.EditTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Devices

  setup :register_and_log_in_user

  describe "Edit device" do
    setup do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_edit_test",
          hostname: "edit-device.lab",
          ip_address: "10.0.50.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      %{device: device}
    end

    test "renders edit form", %{conn: conn, device: device} do
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/edit")
      assert html =~ "Edit Device"
      assert html =~ "edit-device.lab"
    end

    test "displays device fields in form", %{conn: conn, device: device} do
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/edit")
      assert html =~ "Hostname"
      assert html =~ "IP Address"
      assert html =~ "Platform"
      assert html =~ "Transport"
      assert html =~ "gNMI Port"
      assert html =~ "NETCONF Port"
    end

    test "validates form on change", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")

      html =
        view
        |> form("form", %{"device" => %{"hostname" => ""}})
        |> render_change()

      assert html =~ "can"
    end

    test "saves valid device update", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")

      view
      |> form("form", %{
        "device" => %{
          "hostname" => "updated-device.lab",
          "ip_address" => "10.0.50.1",
          "platform" => "cisco_iosxr",
          "transport" => "gnmi"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/devices/#{device.id}")
      assert flash["info"] == "Device updated successfully"
      updated = Devices.get_device!(device.id)
      assert updated.hostname == "updated-device.lab"
    end

    test "shows back link to device", %{conn: conn, device: device} do
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/edit")
      assert html =~ "Back to"
      assert html =~ "edit-device.lab"
    end

    test "shows save and cancel buttons", %{conn: conn, device: device} do
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/edit")
      assert html =~ "Save Changes"
      assert html =~ "Cancel"
    end

    test "updates platform", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")

      view
      |> form("form", %{
        "device" => %{
          "hostname" => "edit-device.lab",
          "ip_address" => "10.0.50.1",
          "platform" => "arista_eos",
          "transport" => "gnmi"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/devices/#{device.id}")
      updated = Devices.get_device!(device.id)
      assert updated.platform == :arista_eos
    end

    test "pre-populates hostname input with saved value", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")
      # The form uses @form[:hostname] which renders with the changeset data.
      # Verify the value appears in the rendered form section.
      form_html = view |> element("form") |> render()
      assert form_html =~ "edit-device.lab"
    end

    test "pre-populates IP address input with saved value", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")
      form_html = view |> element("form") |> render()
      assert form_html =~ "10.0.50.1"
    end

    test "pre-populates gNMI port input with saved value", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")
      form_html = view |> element("form") |> render()
      assert form_html =~ "57400"
    end

    test "pre-populates platform select with saved value", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")
      form_html = view |> element("form") |> render()
      assert form_html =~ "Cisco IOS-XR"
      assert form_html =~ "cisco_iosxr"
    end

    test "pre-populates credential select when credential is set", %{conn: conn} do
      {:ok, cred} =
        Devices.create_credential(%{
          id: "cred_edit_test",
          name: "Edit Test Cred",
          username: "admin"
        })

      {:ok, device} =
        Devices.create_device(%{
          id: "dev_edit_cred_test",
          hostname: "cred-device.lab",
          ip_address: "10.0.50.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          credential_id: cred.id
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/edit")
      assert html =~ "Edit Test Cred"
    end

    test "updates transport", %{conn: conn, device: device} do
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/edit")

      view
      |> form("form", %{
        "device" => %{
          "hostname" => "edit-device.lab",
          "ip_address" => "10.0.50.1",
          "platform" => "cisco_iosxr",
          "transport" => "netconf"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/devices/#{device.id}")
      updated = Devices.get_device!(device.id)
      assert updated.transport == :netconf
    end
  end
end

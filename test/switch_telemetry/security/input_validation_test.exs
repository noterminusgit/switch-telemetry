defmodule SwitchTelemetry.Security.InputValidationTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Devices.Device
  alias SwitchTelemetry.Devices.Credential
  alias SwitchTelemetry.Collector.Subscription
  alias SwitchTelemetry.Alerting.AlertRule
  alias SwitchTelemetry.Alerting.NotificationChannel
  alias SwitchTelemetry.Dashboards.Dashboard

  # --- Device IP validation ---

  describe "Device IP validation" do
    test "accepts valid IPv4" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_ipv4",
          hostname: "sw-01.lab",
          ip_address: "10.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert changeset.valid?
    end

    test "accepts valid IPv6" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_ipv6",
          hostname: "sw-02.lab",
          ip_address: "2001:db8::1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert changeset.valid?
    end

    test "accepts IPv6 full form" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_ipv6_full",
          hostname: "sw-03.lab",
          ip_address: "2001:0db8:0000:0000:0000:0000:0000:0001",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert changeset.valid?
    end

    test "accepts loopback IPv4" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_lo",
          hostname: "sw-04.lab",
          ip_address: "127.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert changeset.valid?
    end

    test "rejects invalid IP address" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_bad_ip",
          hostname: "sw-05.lab",
          ip_address: "not_an_ip",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert "must be a valid IPv4 or IPv6 address" in errors_on(changeset).ip_address
    end

    test "rejects IP with extra octets" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_extra_ip",
          hostname: "sw-06.lab",
          ip_address: "10.0.0.1.5",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert "must be a valid IPv4 or IPv6 address" in errors_on(changeset).ip_address
    end

    test "rejects IP with SQL injection attempt" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_sqli",
          hostname: "sw-07.lab",
          ip_address: "10.0.0.1'; DROP TABLE devices;--",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert "must be a valid IPv4 or IPv6 address" in errors_on(changeset).ip_address
    end
  end

  # --- Device hostname validation ---

  describe "Device hostname validation" do
    test "accepts valid hostname" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_host1",
          hostname: "core-rtr-01.dc1.example.com",
          ip_address: "10.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert changeset.valid?
    end

    test "accepts single-label hostname" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_host2",
          hostname: "router1",
          ip_address: "10.0.0.2",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert changeset.valid?
    end

    test "rejects hostname with spaces" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_host_bad",
          hostname: "bad host name",
          ip_address: "10.0.0.3",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert errors_on(changeset).hostname
    end

    test "rejects hostname starting with hyphen" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_host_hyp",
          hostname: "-invalid.host",
          ip_address: "10.0.0.4",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert errors_on(changeset).hostname
    end

    test "rejects hostname with special characters" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_host_special",
          hostname: "host<script>alert(1)</script>",
          ip_address: "10.0.0.5",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert errors_on(changeset).hostname
    end

    test "rejects hostname exceeding 253 characters" do
      long_hostname = String.duplicate("a", 254)

      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_host_long",
          hostname: long_hostname,
          ip_address: "10.0.0.6",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      refute changeset.valid?
      assert errors_on(changeset).hostname
    end
  end

  # --- Device port validation ---

  describe "Device port validation" do
    test "accepts valid gnmi_port" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_port_ok",
          hostname: "sw-port.lab",
          ip_address: "10.0.0.7",
          platform: :cisco_iosxr,
          transport: :gnmi,
          gnmi_port: 57400
        })

      assert changeset.valid?
    end

    test "rejects gnmi_port of 0" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_port_zero",
          hostname: "sw-port0.lab",
          ip_address: "10.0.0.8",
          platform: :cisco_iosxr,
          transport: :gnmi,
          gnmi_port: 0
        })

      refute changeset.valid?
      assert errors_on(changeset).gnmi_port
    end

    test "rejects gnmi_port above 65535" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_port_high",
          hostname: "sw-port-high.lab",
          ip_address: "10.0.0.9",
          platform: :cisco_iosxr,
          transport: :gnmi,
          gnmi_port: 99999
        })

      refute changeset.valid?
      assert errors_on(changeset).gnmi_port
    end

    test "rejects netconf_port out of range" do
      changeset =
        Device.changeset(%Device{}, %{
          id: "dev_nport",
          hostname: "sw-nport.lab",
          ip_address: "10.0.0.10",
          platform: :cisco_iosxr,
          transport: :netconf,
          netconf_port: -1
        })

      refute changeset.valid?
      assert errors_on(changeset).netconf_port
    end
  end

  # --- Subscription path validation ---

  describe "Subscription path validation" do
    test "accepts valid NETCONF paths" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_valid",
          device_id: "dev_1",
          paths: ["/interfaces/interface/state/counters"]
        })

      assert changeset.valid?
    end

    test "accepts paths with colons (namespaced)" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_ns",
          device_id: "dev_1",
          paths: ["/openconfig-interfaces:interfaces/interface/state"]
        })

      assert changeset.valid?
    end

    test "rejects paths with XML angle brackets" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_xml",
          device_id: "dev_1",
          paths: ["/interfaces/<script>alert(1)</script>"]
        })

      refute changeset.valid?
      assert errors_on(changeset).paths
    end

    test "rejects paths with ampersand" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_amp",
          device_id: "dev_1",
          paths: ["/interfaces&entity;/state"]
        })

      refute changeset.valid?
      assert errors_on(changeset).paths
    end

    test "rejects paths with SQL comment sequence" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_sql",
          device_id: "dev_1",
          paths: ["/interfaces/--; DROP TABLE metrics"]
        })

      refute changeset.valid?
      assert errors_on(changeset).paths
    end

    test "rejects paths not starting with slash" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_noslash",
          device_id: "dev_1",
          paths: ["interfaces/interface"]
        })

      refute changeset.valid?
      assert errors_on(changeset).paths
    end

    test "rejects paths exceeding 512 characters" do
      long_path = "/" <> String.duplicate("a", 512)

      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_long",
          device_id: "dev_1",
          paths: [long_path]
        })

      refute changeset.valid?
      assert errors_on(changeset).paths
    end

    test "rejects if any path in list is invalid" do
      changeset =
        Subscription.changeset(%Subscription{}, %{
          id: "sub_mixed",
          device_id: "dev_1",
          paths: ["/valid/path", "/invalid/<path>"]
        })

      refute changeset.valid?
      assert errors_on(changeset).paths
    end
  end

  # --- Credential string length limits ---

  describe "Credential string length limits" do
    test "rejects name exceeding 255 characters" do
      changeset =
        Credential.changeset(%Credential{}, %{
          id: "cred_long",
          name: String.duplicate("a", 256),
          username: "admin"
        })

      refute changeset.valid?
      assert errors_on(changeset).name
    end

    test "rejects username exceeding 255 characters" do
      changeset =
        Credential.changeset(%Credential{}, %{
          id: "cred_long_user",
          name: "test-cred",
          username: String.duplicate("u", 256)
        })

      refute changeset.valid?
      assert errors_on(changeset).username
    end

    test "accepts valid credential" do
      changeset =
        Credential.changeset(%Credential{}, %{
          id: "cred_ok",
          name: "lab-credentials",
          username: "admin"
        })

      assert changeset.valid?
    end
  end

  # --- AlertRule string length limits ---

  describe "AlertRule string length limits" do
    test "rejects name exceeding 255 characters" do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          id: "rule_long",
          name: String.duplicate("a", 256),
          path: "/interfaces/interface/state/counters",
          condition: :above,
          threshold: 90.0
        })

      refute changeset.valid?
      assert errors_on(changeset).name
    end

    test "rejects description exceeding 1000 characters" do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          id: "rule_long_desc",
          name: "valid-rule",
          path: "/interfaces/interface/state/counters",
          condition: :above,
          threshold: 90.0,
          description: String.duplicate("d", 1001)
        })

      refute changeset.valid?
      assert errors_on(changeset).description
    end

    test "rejects path exceeding 512 characters" do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          id: "rule_long_path",
          name: "valid-rule-2",
          path: "/" <> String.duplicate("p", 512),
          condition: :above,
          threshold: 90.0
        })

      refute changeset.valid?
      assert errors_on(changeset).path
    end
  end

  # --- NotificationChannel string length limits ---

  describe "NotificationChannel string length limits" do
    test "rejects name exceeding 255 characters" do
      changeset =
        NotificationChannel.changeset(%NotificationChannel{}, %{
          id: "chan_long",
          name: String.duplicate("a", 256),
          type: :webhook,
          config: %{"url" => "https://example.com/hook"}
        })

      refute changeset.valid?
      assert errors_on(changeset).name
    end

    test "accepts valid notification channel" do
      changeset =
        NotificationChannel.changeset(%NotificationChannel{}, %{
          id: "chan_ok",
          name: "slack-alerts",
          type: :slack,
          config: %{"webhook_url" => "https://hooks.slack.com/test"}
        })

      assert changeset.valid?
    end
  end

  # --- Dashboard string length limits ---

  describe "Dashboard string length limits" do
    test "rejects name exceeding 255 characters" do
      changeset =
        Dashboard.changeset(%Dashboard{}, %{
          id: "dash_long",
          name: String.duplicate("a", 256)
        })

      refute changeset.valid?
      assert errors_on(changeset).name
    end

    test "rejects description exceeding 1000 characters" do
      changeset =
        Dashboard.changeset(%Dashboard{}, %{
          id: "dash_long_desc",
          name: "valid-dashboard",
          description: String.duplicate("d", 1001)
        })

      refute changeset.valid?
      assert errors_on(changeset).description
    end

    test "accepts valid dashboard" do
      changeset =
        Dashboard.changeset(%Dashboard{}, %{
          id: "dash_ok",
          name: "Network Overview"
        })

      assert changeset.valid?
    end
  end
end

defmodule SwitchTelemetry.Devices.DeviceTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Devices.Device

  @valid_attrs %{
    id: "dev_test001",
    hostname: "core-sw-01.dc1.example.com",
    ip_address: "10.0.1.1",
    platform: :cisco_iosxr,
    transport: :gnmi
  }

  describe "changeset/2" do
    test "valid attributes" do
      changeset = Device.changeset(%Device{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires hostname" do
      attrs = Map.delete(@valid_attrs, :hostname)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{hostname: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires ip_address" do
      attrs = Map.delete(@valid_attrs, :ip_address)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{ip_address: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires platform" do
      attrs = Map.delete(@valid_attrs, :platform)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{platform: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires transport" do
      attrs = Map.delete(@valid_attrs, :transport)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{transport: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates platform enum values" do
      attrs = Map.put(@valid_attrs, :platform, :invalid)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{platform: ["is invalid"]} = errors_on(changeset)
    end

    test "validates transport enum values" do
      attrs = Map.put(@valid_attrs, :transport, :invalid)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{transport: ["is invalid"]} = errors_on(changeset)
    end

    test "cisco_iosxe is a valid platform value" do
      attrs = Map.put(@valid_attrs, :platform, :cisco_iosxe)
      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
    end

    test "all platform values are valid" do
      for platform <- [
            :cisco_iosxr,
            :cisco_iosxe,
            :cisco_nxos,
            :juniper_junos,
            :arista_eos,
            :nokia_sros
          ] do
        attrs = Map.put(@valid_attrs, :platform, platform)
        changeset = Device.changeset(%Device{}, attrs)
        assert changeset.valid?, "Expected #{platform} to be a valid platform"
      end
    end

    test "defaults gnmi_port to 57400" do
      changeset = Device.changeset(%Device{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :gnmi_port) == 57400
    end

    test "defaults status to active" do
      changeset = Device.changeset(%Device{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == :active
    end

    test "defaults secure_mode to insecure" do
      changeset = Device.changeset(%Device{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :secure_mode) == :insecure
    end

    test "all secure_mode enum values are accepted" do
      for mode <- [:insecure, :tls_skip_verify] do
        attrs = Map.put(@valid_attrs, :secure_mode, mode)
        changeset = Device.changeset(%Device{}, attrs)
        assert changeset.valid?, "Expected #{mode} to be a valid secure_mode"
      end

      # tls_verified and mtls require a credential for gNMI transport
      for mode <- [:tls_verified, :mtls] do
        attrs = Map.merge(@valid_attrs, %{secure_mode: mode, credential_id: "cred_test001"})
        changeset = Device.changeset(%Device{}, attrs)

        refute Map.has_key?(errors_on(changeset), :secure_mode),
               "Expected #{mode} to be a valid secure_mode"
      end
    end

    test "invalid secure_mode value is rejected" do
      attrs = Map.put(@valid_attrs, :secure_mode, :invalid_mode)
      changeset = Device.changeset(%Device{}, attrs)
      assert %{secure_mode: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "secure_mode validation" do
    test "tls_verified + gnmi transport + no credential_id is invalid" do
      attrs = Map.merge(@valid_attrs, %{secure_mode: :tls_verified, transport: :gnmi})
      changeset = Device.changeset(%Device{}, attrs)

      assert %{credential_id: ["is required for TLS-verified gNMI transport"]} =
               errors_on(changeset)
    end

    test "tls_verified + gnmi transport + credential_id present is valid" do
      attrs =
        Map.merge(@valid_attrs, %{
          secure_mode: :tls_verified,
          transport: :gnmi,
          credential_id: "cred_test001"
        })

      changeset = Device.changeset(%Device{}, attrs)
      refute Map.has_key?(errors_on(changeset), :credential_id)
    end

    test "mtls + gnmi transport + no credential_id is invalid" do
      attrs = Map.merge(@valid_attrs, %{secure_mode: :mtls, transport: :gnmi})
      changeset = Device.changeset(%Device{}, attrs)

      assert %{credential_id: ["is required for TLS-verified gNMI transport"]} =
               errors_on(changeset)
    end

    test "mtls + gnmi transport + credential_id present is valid" do
      attrs =
        Map.merge(@valid_attrs, %{
          secure_mode: :mtls,
          transport: :gnmi,
          credential_id: "cred_test001"
        })

      changeset = Device.changeset(%Device{}, attrs)
      refute Map.has_key?(errors_on(changeset), :credential_id)
    end

    test "insecure + gnmi transport + no credential_id is valid" do
      attrs = Map.merge(@valid_attrs, %{secure_mode: :insecure, transport: :gnmi})
      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
    end

    test "tls_skip_verify + gnmi transport + no credential_id is valid" do
      attrs = Map.merge(@valid_attrs, %{secure_mode: :tls_skip_verify, transport: :gnmi})
      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
    end

    test "tls_verified + netconf transport + no credential_id is valid" do
      attrs = Map.merge(@valid_attrs, %{secure_mode: :tls_verified, transport: :netconf})
      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
    end

    test "tls_verified + both transport + no credential_id is invalid" do
      attrs = Map.merge(@valid_attrs, %{secure_mode: :tls_verified, transport: :both})
      changeset = Device.changeset(%Device{}, attrs)

      assert %{credential_id: ["is required for TLS-verified gNMI transport"]} =
               errors_on(changeset)
    end

    test "tls_verified + both transport + credential_id present is valid" do
      attrs =
        Map.merge(@valid_attrs, %{
          secure_mode: :tls_verified,
          transport: :both,
          credential_id: "cred_test001"
        })

      changeset = Device.changeset(%Device{}, attrs)
      refute Map.has_key?(errors_on(changeset), :credential_id)
    end
  end
end

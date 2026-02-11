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

    test "defaults gnmi_port to 57400" do
      changeset = Device.changeset(%Device{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :gnmi_port) == 57400
    end

    test "defaults status to active" do
      changeset = Device.changeset(%Device{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == :active
    end
  end
end

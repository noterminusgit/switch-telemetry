defmodule SwitchTelemetry.Devices.CredentialTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Devices.Credential

  @valid_attrs %{
    id: "cred_test001",
    name: "Test Credentials",
    username: "telemetry_ro",
    password: "secret123"
  }

  describe "changeset/2" do
    test "valid attributes" do
      changeset = Credential.changeset(%Credential{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = Credential.changeset(%Credential{}, attrs)
      assert %{id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = Credential.changeset(%Credential{}, attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires username" do
      attrs = Map.delete(@valid_attrs, :username)
      changeset = Credential.changeset(%Credential{}, attrs)
      assert %{username: ["can't be blank"]} = errors_on(changeset)
    end

    test "password is optional" do
      attrs = Map.delete(@valid_attrs, :password)
      changeset = Credential.changeset(%Credential{}, attrs)
      assert changeset.valid?
    end
  end
end

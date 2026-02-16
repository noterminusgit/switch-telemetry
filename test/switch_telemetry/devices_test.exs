defmodule SwitchTelemetry.DevicesTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Devices

  defp valid_device_attrs(overrides \\ %{}) do
    n = System.unique_integer([:positive])
    id = "dev-#{n}"

    Map.merge(
      %{
        id: id,
        hostname: "switch-#{n}",
        ip_address: "10.0.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
        platform: :cisco_iosxr,
        transport: :gnmi
      },
      overrides
    )
  end

  defp valid_credential_attrs(overrides \\ %{}) do
    id = "cred_#{System.unique_integer([:positive])}"

    Map.merge(
      %{
        id: id,
        name: "cred-#{id}",
        username: "admin"
      },
      overrides
    )
  end

  # --- Device CRUD ---

  describe "list_devices/0" do
    test "returns empty list when no devices" do
      assert Devices.list_devices() == []
    end

    test "returns all devices" do
      {:ok, _} = Devices.create_device(valid_device_attrs())
      {:ok, _} = Devices.create_device(valid_device_attrs())
      assert length(Devices.list_devices()) == 2
    end
  end

  describe "list_devices_by_status/1" do
    test "filters devices by status" do
      {:ok, _} = Devices.create_device(valid_device_attrs(%{status: :active}))
      {:ok, _} = Devices.create_device(valid_device_attrs(%{status: :inactive}))
      {:ok, _} = Devices.create_device(valid_device_attrs(%{status: :active}))

      active = Devices.list_devices_by_status(:active)
      assert length(active) == 2

      inactive = Devices.list_devices_by_status(:inactive)
      assert length(inactive) == 1
    end

    test "returns empty list for status with no matches" do
      {:ok, _} = Devices.create_device(valid_device_attrs(%{status: :active}))
      assert Devices.list_devices_by_status(:maintenance) == []
    end
  end

  describe "get_device!/1" do
    test "returns device by id" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      found = Devices.get_device!(device.id)
      assert found.id == device.id
      assert found.hostname == device.hostname
    end

    test "raises for missing device" do
      assert_raise Ecto.NoResultsError, fn ->
        Devices.get_device!("nonexistent")
      end
    end
  end

  describe "get_device/1" do
    test "returns device when found" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      assert Devices.get_device(device.id) != nil
      assert Devices.get_device(device.id).id == device.id
    end

    test "returns nil for missing device" do
      assert Devices.get_device("nonexistent") == nil
    end
  end

  describe "create_device/1" do
    test "creates device with valid attrs" do
      attrs = valid_device_attrs()
      assert {:ok, device} = Devices.create_device(attrs)
      assert device.hostname == attrs.hostname
      assert device.ip_address == attrs.ip_address
      assert device.platform == :cisco_iosxr
      assert device.transport == :gnmi
    end

    test "applies default values" do
      attrs = valid_device_attrs()
      assert {:ok, device} = Devices.create_device(attrs)
      assert device.gnmi_port == 57400
      assert device.netconf_port == 830
      assert device.collection_interval_ms == 30_000
      assert device.status == :active
    end

    test "creates device with all platforms" do
      for platform <- [:cisco_iosxr, :cisco_nxos, :juniper_junos, :arista_eos, :nokia_sros] do
        attrs = valid_device_attrs(%{platform: platform})
        assert {:ok, device} = Devices.create_device(attrs)
        assert device.platform == platform
      end
    end

    test "creates device with all transport types" do
      for transport <- [:gnmi, :netconf, :both] do
        attrs = valid_device_attrs(%{transport: transport})
        assert {:ok, device} = Devices.create_device(attrs)
        assert device.transport == transport
      end
    end

    test "rejects missing required fields" do
      assert {:error, changeset} = Devices.create_device(%{})
      errors = errors_on(changeset)
      assert errors.id
      assert errors.hostname
      assert errors.ip_address
      assert errors.platform
      assert errors.transport
    end

    test "rejects invalid IP address" do
      attrs = valid_device_attrs(%{ip_address: "not-an-ip"})
      assert {:error, changeset} = Devices.create_device(attrs)
      assert errors_on(changeset).ip_address
    end

    test "accepts valid IPv6 address" do
      attrs = valid_device_attrs(%{ip_address: "2001:db8::1"})
      assert {:ok, device} = Devices.create_device(attrs)
      assert device.ip_address == "2001:db8::1"
    end

    test "rejects duplicate hostname" do
      attrs = valid_device_attrs(%{hostname: "unique-host"})
      {:ok, _} = Devices.create_device(attrs)
      attrs2 = valid_device_attrs(%{hostname: "unique-host"})
      assert {:error, changeset} = Devices.create_device(attrs2)
      assert errors_on(changeset).hostname
    end

    test "rejects duplicate ip_address" do
      attrs = valid_device_attrs(%{ip_address: "192.168.1.100"})
      {:ok, _} = Devices.create_device(attrs)
      attrs2 = valid_device_attrs(%{ip_address: "192.168.1.100"})
      assert {:error, changeset} = Devices.create_device(attrs2)
      assert errors_on(changeset).ip_address
    end

    test "creates device with optional fields" do
      attrs =
        valid_device_attrs(%{
          gnmi_port: 9339,
          netconf_port: 8300,
          collection_interval_ms: 60_000,
          status: :maintenance,
          assigned_collector: "collector1@host",
          tags: %{"env" => "prod", "region" => "us-east"}
        })

      assert {:ok, device} = Devices.create_device(attrs)
      assert device.gnmi_port == 9339
      assert device.netconf_port == 8300
      assert device.collection_interval_ms == 60_000
      assert device.status == :maintenance
      assert device.assigned_collector == "collector1@host"
      assert device.tags == %{"env" => "prod", "region" => "us-east"}
    end
  end

  describe "update_device/2" do
    test "updates device fields" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      assert {:ok, updated} = Devices.update_device(device, %{status: :maintenance})
      assert updated.status == :maintenance
    end

    test "updates multiple fields" do
      {:ok, device} = Devices.create_device(valid_device_attrs())

      assert {:ok, updated} =
               Devices.update_device(device, %{
                 status: :unreachable,
                 gnmi_port: 50051,
                 collection_interval_ms: 60_000
               })

      assert updated.status == :unreachable
      assert updated.gnmi_port == 50051
      assert updated.collection_interval_ms == 60_000
    end

    test "rejects invalid updates" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      assert {:error, changeset} = Devices.update_device(device, %{ip_address: "bad"})
      assert errors_on(changeset).ip_address
    end
  end

  describe "delete_device/1" do
    test "deletes device" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      assert {:ok, _} = Devices.delete_device(device)
      assert Devices.get_device(device.id) == nil
    end
  end

  describe "list_devices_for_collector/1" do
    test "returns active devices assigned to collector" do
      {:ok, _} =
        Devices.create_device(
          valid_device_attrs(%{assigned_collector: "node1@host", status: :active})
        )

      {:ok, _} =
        Devices.create_device(
          valid_device_attrs(%{assigned_collector: "node1@host", status: :inactive})
        )

      {:ok, _} =
        Devices.create_device(
          valid_device_attrs(%{assigned_collector: "node2@host", status: :active})
        )

      result = Devices.list_devices_for_collector("node1@host")
      assert length(result) == 1
      assert hd(result).assigned_collector == "node1@host"
      assert hd(result).status == :active
    end

    test "returns empty list when no matches" do
      assert Devices.list_devices_for_collector("nonexistent@host") == []
    end
  end

  # --- Credential CRUD ---

  describe "create_credential/1" do
    test "creates credential with valid attrs" do
      attrs = valid_credential_attrs()
      assert {:ok, cred} = Devices.create_credential(attrs)
      assert cred.username == "admin"
      assert cred.name == attrs.name
    end

    test "creates credential with optional fields" do
      attrs = valid_credential_attrs(%{password: "secret123", ssh_key: "ssh-rsa AAAA..."})
      assert {:ok, cred} = Devices.create_credential(attrs)
      assert cred.username == "admin"
    end

    test "rejects missing required fields" do
      assert {:error, changeset} = Devices.create_credential(%{})
      errors = errors_on(changeset)
      assert errors.id
      assert errors.name
      assert errors.username
    end

    test "rejects duplicate name" do
      attrs = valid_credential_attrs(%{name: "shared-cred"})
      {:ok, _} = Devices.create_credential(attrs)
      attrs2 = valid_credential_attrs(%{name: "shared-cred"})
      assert {:error, changeset} = Devices.create_credential(attrs2)
      assert errors_on(changeset).name
    end
  end

  describe "get_credential!/1" do
    test "returns credential by id" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      found = Devices.get_credential!(cred.id)
      assert found.id == cred.id
      assert found.username == cred.username
    end

    test "raises for missing credential" do
      assert_raise Ecto.NoResultsError, fn ->
        Devices.get_credential!("nonexistent")
      end
    end
  end

  describe "get_credential/1" do
    test "returns credential when found" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      assert Devices.get_credential(cred.id) != nil
    end

    test "returns nil for missing credential" do
      assert Devices.get_credential("nonexistent") == nil
    end
  end

  describe "update_credential/2" do
    test "updates credential fields" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      assert {:ok, updated} = Devices.update_credential(cred, %{username: "operator"})
      assert updated.username == "operator"
    end
  end

  describe "delete_credential/1" do
    test "deletes credential" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      assert {:ok, _} = Devices.delete_credential(cred)
      assert Devices.get_credential(cred.id) == nil
    end
  end

  describe "device-credential association" do
    test "creates device with credential_id" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      attrs = valid_device_attrs(%{credential_id: cred.id})
      assert {:ok, device} = Devices.create_device(attrs)
      assert device.credential_id == cred.id
    end
  end

  # --- Additional coverage tests ---

  describe "change_device/1" do
    test "returns a changeset for an existing device" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      changeset = Devices.change_device(device)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_device/2" do
    test "returns a changeset with new attributes" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      changeset = Devices.change_device(device, %{hostname: "updated.lab"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :hostname) == "updated.lab"
    end

    test "returns a changeset that tracks status change" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      changeset = Devices.change_device(device, %{status: :maintenance})
      assert Ecto.Changeset.get_change(changeset, :status) == :maintenance
    end

    test "returns an invalid changeset for bad ip_address" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      changeset = Devices.change_device(device, %{ip_address: "not-valid"})
      refute changeset.valid?
    end
  end

  describe "get_device_with_credential!/1" do
    test "returns device with preloaded credential (nil)" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      result = Devices.get_device_with_credential!(device.id)
      assert result.id == device.id
      # credential is preloaded as nil when not set
      assert is_nil(result.credential)
    end

    test "returns device with preloaded credential association" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      {:ok, device} = Devices.create_device(valid_device_attrs(%{credential_id: cred.id}))
      result = Devices.get_device_with_credential!(device.id)
      assert result.id == device.id
      assert result.credential.id == cred.id
      assert result.credential.name == cred.name
    end

    test "raises for missing device" do
      assert_raise Ecto.NoResultsError, fn ->
        Devices.get_device_with_credential!("nonexistent")
      end
    end
  end

  describe "get_device_with_subscriptions!/1" do
    test "returns device with preloaded subscriptions (empty)" do
      {:ok, device} = Devices.create_device(valid_device_attrs())
      result = Devices.get_device_with_subscriptions!(device.id)
      assert result.id == device.id
      assert is_list(result.subscriptions)
      assert result.subscriptions == []
    end

    test "raises for missing device" do
      assert_raise Ecto.NoResultsError, fn ->
        Devices.get_device_with_subscriptions!("nonexistent")
      end
    end
  end

  describe "list_credentials_for_select/0" do
    test "returns empty list when no credentials" do
      assert Devices.list_credentials_for_select() == []
    end

    test "returns {name, id} tuples" do
      {:ok, cred} =
        Devices.create_credential(valid_credential_attrs(%{name: "Select Test Cred"}))

      result = Devices.list_credentials_for_select()
      assert {"Select Test Cred", cred.id} in result
    end

    test "returns credentials sorted by name" do
      {:ok, _} =
        Devices.create_credential(valid_credential_attrs(%{name: "Bravo Cred"}))

      {:ok, _} =
        Devices.create_credential(valid_credential_attrs(%{name: "Alpha Cred"}))

      result = Devices.list_credentials_for_select()
      names = Enum.map(result, fn {name, _id} -> name end)
      assert names == ["Alpha Cred", "Bravo Cred"]
    end

    test "returns all credentials" do
      {:ok, _} = Devices.create_credential(valid_credential_attrs(%{name: "One"}))
      {:ok, _} = Devices.create_credential(valid_credential_attrs(%{name: "Two"}))
      {:ok, _} = Devices.create_credential(valid_credential_attrs(%{name: "Three"}))

      result = Devices.list_credentials_for_select()
      assert length(result) == 3
    end
  end

  describe "change_credential/1" do
    test "returns a changeset" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      changeset = Devices.change_credential(cred)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_credential/2" do
    test "returns a changeset with changes" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      changeset = Devices.change_credential(cred, %{username: "operator"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :username) == "operator"
    end

    test "returns a changeset with name change" do
      {:ok, cred} = Devices.create_credential(valid_credential_attrs())
      changeset = Devices.change_credential(cred, %{name: "New Name"})
      assert Ecto.Changeset.get_change(changeset, :name) == "New Name"
    end
  end

  describe "list_credentials/0" do
    test "returns empty list when no credentials exist" do
      assert Devices.list_credentials() == []
    end

    test "returns all credentials" do
      {:ok, _} = Devices.create_credential(valid_credential_attrs())
      {:ok, _} = Devices.create_credential(valid_credential_attrs())
      assert length(Devices.list_credentials()) == 2
    end
  end
end

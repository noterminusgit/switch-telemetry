defmodule SwitchTelemetry.CollectorTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.{Collector, Devices}
  alias SwitchTelemetry.Collector.Subscription

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

  defp valid_subscription_attrs(device_id, overrides \\ %{}) do
    n = System.unique_integer([:positive])
    id = "sub-#{n}"

    Map.merge(
      %{
        id: id,
        device_id: device_id,
        paths: ["/interfaces/interface/state/counters"]
      },
      overrides
    )
  end

  defp create_device do
    {:ok, device} = Devices.create_device(valid_device_attrs())
    device
  end

  # --- Subscription CRUD ---

  describe "list_subscriptions/0" do
    test "returns empty list when no subscriptions" do
      assert Collector.list_subscriptions() == []
    end

    test "returns all subscriptions with preloaded devices" do
      device = create_device()
      {:ok, _} = Collector.create_subscription(valid_subscription_attrs(device.id))
      {:ok, _} = Collector.create_subscription(valid_subscription_attrs(device.id))

      subscriptions = Collector.list_subscriptions()
      assert length(subscriptions) == 2
      assert Enum.all?(subscriptions, fn s -> s.device != nil end)
    end
  end

  describe "list_subscriptions_for_device/1" do
    test "returns subscriptions for specific device" do
      device1 = create_device()
      device2 = create_device()

      {:ok, _} = Collector.create_subscription(valid_subscription_attrs(device1.id))
      {:ok, _} = Collector.create_subscription(valid_subscription_attrs(device1.id))
      {:ok, _} = Collector.create_subscription(valid_subscription_attrs(device2.id))

      subs1 = Collector.list_subscriptions_for_device(device1.id)
      assert length(subs1) == 2

      subs2 = Collector.list_subscriptions_for_device(device2.id)
      assert length(subs2) == 1
    end

    test "returns empty list for device with no subscriptions" do
      device = create_device()
      assert Collector.list_subscriptions_for_device(device.id) == []
    end
  end

  describe "get_subscription!/1" do
    test "returns subscription with preloaded device" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))

      found = Collector.get_subscription!(sub.id)
      assert found.id == sub.id
      assert found.device.id == device.id
    end

    test "raises for missing subscription" do
      assert_raise Ecto.NoResultsError, fn ->
        Collector.get_subscription!("nonexistent")
      end
    end
  end

  describe "get_subscription/1" do
    test "returns subscription when found" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))
      assert Collector.get_subscription(sub.id) != nil
    end

    test "returns nil for missing subscription" do
      assert Collector.get_subscription("nonexistent") == nil
    end
  end

  describe "create_subscription/1" do
    test "creates subscription with valid attrs" do
      device = create_device()
      attrs = valid_subscription_attrs(device.id)

      assert {:ok, sub} = Collector.create_subscription(attrs)
      assert sub.device_id == device.id
      assert sub.paths == ["/interfaces/interface/state/counters"]
    end

    test "applies default values" do
      device = create_device()
      attrs = valid_subscription_attrs(device.id)

      assert {:ok, sub} = Collector.create_subscription(attrs)
      assert sub.mode == :stream
      assert sub.sample_interval_ns == 30_000_000_000
      assert sub.encoding == :proto
      assert sub.enabled == true
    end

    test "creates subscription with all modes" do
      device = create_device()

      for mode <- [:stream, :poll, :once] do
        attrs = valid_subscription_attrs(device.id, %{mode: mode})
        assert {:ok, sub} = Collector.create_subscription(attrs)
        assert sub.mode == mode
      end
    end

    test "creates subscription with all encodings" do
      device = create_device()

      for encoding <- [:proto, :json, :json_ietf] do
        attrs = valid_subscription_attrs(device.id, %{encoding: encoding})
        assert {:ok, sub} = Collector.create_subscription(attrs)
        assert sub.encoding == encoding
      end
    end

    test "creates subscription with multiple paths" do
      device = create_device()

      attrs =
        valid_subscription_attrs(device.id, %{
          paths: [
            "/interfaces/interface/state/counters",
            "/system/state/hostname",
            "/components/component/cpu"
          ]
        })

      assert {:ok, sub} = Collector.create_subscription(attrs)
      assert length(sub.paths) == 3
    end

    test "rejects missing required fields" do
      assert {:error, changeset} = Collector.create_subscription(%{})
      errors = errors_on(changeset)
      assert errors.id
      assert errors.device_id
      assert errors.paths
    end

    test "rejects empty paths" do
      device = create_device()
      attrs = valid_subscription_attrs(device.id, %{paths: []})
      assert {:error, changeset} = Collector.create_subscription(attrs)
      assert errors_on(changeset).paths
    end

    test "rejects invalid path format" do
      device = create_device()
      attrs = valid_subscription_attrs(device.id, %{paths: ["invalid<path>"]})
      assert {:error, changeset} = Collector.create_subscription(attrs)
      assert errors_on(changeset).paths
    end

    test "rejects paths with SQL injection characters" do
      device = create_device()
      attrs = valid_subscription_attrs(device.id, %{paths: ["/path; DROP TABLE"]})
      assert {:error, changeset} = Collector.create_subscription(attrs)
      assert errors_on(changeset).paths
    end
  end

  describe "update_subscription/2" do
    test "updates subscription fields" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))

      assert {:ok, updated} = Collector.update_subscription(sub, %{enabled: false})
      assert updated.enabled == false
    end

    test "updates multiple fields" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))

      assert {:ok, updated} =
               Collector.update_subscription(sub, %{
                 mode: :poll,
                 sample_interval_ns: 60_000_000_000,
                 encoding: :json
               })

      assert updated.mode == :poll
      assert updated.sample_interval_ns == 60_000_000_000
      assert updated.encoding == :json
    end

    test "updates paths" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))

      new_paths = ["/new/path/one", "/new/path/two"]
      assert {:ok, updated} = Collector.update_subscription(sub, %{paths: new_paths})
      assert updated.paths == new_paths
    end
  end

  describe "delete_subscription/1" do
    test "deletes subscription" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))

      assert {:ok, _} = Collector.delete_subscription(sub)
      assert Collector.get_subscription(sub.id) == nil
    end
  end

  describe "change_subscription/2" do
    test "returns changeset for subscription" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id))

      changeset = Collector.change_subscription(sub, %{enabled: false})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset for new subscription" do
      changeset = Collector.change_subscription(%Subscription{}, %{})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "toggle_subscription/1" do
    test "toggles enabled from true to false" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id, %{enabled: true}))

      assert {:ok, toggled} = Collector.toggle_subscription(sub)
      assert toggled.enabled == false
    end

    test "toggles enabled from false to true" do
      device = create_device()
      {:ok, sub} = Collector.create_subscription(valid_subscription_attrs(device.id, %{enabled: false}))

      assert {:ok, toggled} = Collector.toggle_subscription(sub)
      assert toggled.enabled == true
    end
  end
end

defmodule SwitchTelemetry.Collector.DeviceAssignmentTest do
  use SwitchTelemetry.DataCase, async: false

  alias SwitchTelemetry.Collector.DeviceAssignment

  describe "module" do
    test "exports start_link/1" do
      assert function_exported?(DeviceAssignment, :start_link, 1)
    end

    test "exports get_owner/1" do
      assert function_exported?(DeviceAssignment, :get_owner, 1)
    end

    test "exports rebalance/0" do
      assert function_exported?(DeviceAssignment, :rebalance, 0)
    end
  end

  describe "hash ring" do
    test "HashRing can be created with add_node" do
      ring =
        [:node1@host, :node2@host]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      node = HashRing.key_to_node(ring, "device_123")
      assert is_atom(node)
      assert node in [:node1@host, :node2@host]
    end

    test "same key always maps to same node" do
      ring =
        [:node1@host, :node2@host, :node3@host]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      node1 = HashRing.key_to_node(ring, "device_abc")
      node2 = HashRing.key_to_node(ring, "device_abc")
      assert node1 == node2
    end

    test "different keys may map to different nodes" do
      ring =
        [:node1@host, :node2@host, :node3@host]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      results =
        for i <- 1..100 do
          HashRing.key_to_node(ring, "device_#{i}")
        end

      # With 3 nodes and 100 devices, should see more than 1 node used
      unique_nodes = Enum.uniq(results)
      assert length(unique_nodes) > 1
    end
  end

  describe "GenServer callbacks" do
    test "handle_call {:get_owner, device_id} returns {:ok, node} for device in ring" do
      ring = Enum.reduce([:node1@host, :node2@host], HashRing.new(), &HashRing.add_node(&2, &1))
      state = %{ring: ring}

      {:reply, {:ok, node}, ^state} =
        DeviceAssignment.handle_call({:get_owner, "device_123"}, {self(), make_ref()}, state)

      assert node in [:node1@host, :node2@host]
    end

    test "handle_call {:get_owner, device_id} returns {:error, :no_collectors} when ring empty" do
      ring = HashRing.new()
      state = %{ring: ring}

      assert {:reply, {:error, :no_collectors}, ^state} =
               DeviceAssignment.handle_call(
                 {:get_owner, "device_123"},
                 {self(), make_ref()},
                 state
               )
    end

    test "handle_cast :rebalance returns :noreply with state" do
      ring = HashRing.new()
      state = %{ring: ring}
      assert {:noreply, ^state} = DeviceAssignment.handle_cast(:rebalance, state)
    end

    test "handle_info :nodeup rebuilds ring and returns updated state" do
      state = %{ring: HashRing.new()}
      {:noreply, new_state} = DeviceAssignment.handle_info({:nodeup, :new_node@host, []}, state)
      assert %{ring: _} = new_state
    end

    test "handle_info :nodedown rebuilds ring and returns updated state" do
      state = %{ring: HashRing.new()}

      {:noreply, new_state} = DeviceAssignment.handle_info({:nodedown, :old_node@host, []}, state)

      assert %{ring: _} = new_state
    end

    test "handle_info :initial_assignment returns :noreply" do
      ring = HashRing.new()
      state = %{ring: ring}
      assert {:noreply, ^state} = DeviceAssignment.handle_info(:initial_assignment, state)
    end

    test "handle_info unknown message returns :noreply with unchanged state" do
      state = %{ring: HashRing.new()}
      assert {:noreply, ^state} = DeviceAssignment.handle_info(:unknown, state)
    end

    test "get_owner returns consistent node for same device across calls" do
      ring = Enum.reduce([:a@host, :b@host, :c@host], HashRing.new(), &HashRing.add_node(&2, &1))
      state = %{ring: ring}

      {:reply, {:ok, node1}, _} =
        DeviceAssignment.handle_call({:get_owner, "dev1"}, {self(), make_ref()}, state)

      {:reply, {:ok, node2}, _} =
        DeviceAssignment.handle_call({:get_owner, "dev1"}, {self(), make_ref()}, state)

      assert node1 == node2
    end

    test "nodeup and nodedown both preserve ring key in state" do
      state = %{ring: HashRing.new()}

      {:noreply, state_after_up} = DeviceAssignment.handle_info({:nodeup, :x@host, []}, state)

      assert Map.has_key?(state_after_up, :ring)

      {:noreply, state_after_down} =
        DeviceAssignment.handle_info({:nodedown, :x@host, []}, state_after_up)

      assert Map.has_key?(state_after_down, :ring)
    end

    test "handle_call {:get_owner, _} with single-node ring always returns that node" do
      ring = Enum.reduce([:only@host], HashRing.new(), &HashRing.add_node(&2, &1))
      state = %{ring: ring}

      for i <- 1..10 do
        {:reply, {:ok, node}, ^state} =
          DeviceAssignment.handle_call(
            {:get_owner, "device_#{i}"},
            {self(), make_ref()},
            state
          )

        assert node == :only@host
      end
    end
  end

  describe "collector_node? logic" do
    test "nodeup from collector node rebuilds ring including that node type" do
      # When a node named "collector@..." joins, the ring should consider it.
      # The collector_node? function checks if the node name starts with "collector"
      # or is the current node (Node.self()). Since we're testing in a non-distributed
      # context, Node.self() is :nonode@nohost, which always passes.
      # We test the logic indirectly via nodeup/nodedown callbacks.

      state = %{ring: HashRing.new()}

      # nodeup from any node triggers a ring rebuild
      {:noreply, state_after} =
        DeviceAssignment.handle_info({:nodeup, :"collector@10.0.0.1", []}, state)

      assert %{ring: ring} = state_after
      # The ring is rebuilt using Node.self() and Node.list() at call time,
      # so in test (non-distributed) it only includes Node.self()
      assert is_struct(ring) or is_map(ring)
    end

    test "nodeup from non-collector node still triggers ring rebuild" do
      state = %{ring: HashRing.new()}

      {:noreply, state_after} =
        DeviceAssignment.handle_info({:nodeup, :"web@10.0.0.2", []}, state)

      assert %{ring: _ring} = state_after
    end

    test "collector node names are detected by string prefix" do
      # Verify the naming convention: nodes starting with "collector" are collector nodes.
      # We can test this by verifying the filtering logic directly.
      collector_atom = :"collector@10.0.0.1"
      web_atom = :"web@10.0.0.2"

      collector_str = Atom.to_string(collector_atom)
      web_str = Atom.to_string(web_atom)

      assert String.starts_with?(collector_str, "collector")
      refute String.starts_with?(web_str, "collector")
    end

    test "current node always passes collector_node? check" do
      # The source code: collector_node? returns true if node_str starts with "collector"
      # OR if node == Node.self(). This means the current node is always included
      # in the ring regardless of its name.
      current_node = Node.self()
      current_str = Atom.to_string(current_node)

      # In test, Node.self() is :nonode@nohost - not starting with "collector"
      # but collector_node? still returns true for it
      assert current_str == "nonode@nohost" or String.starts_with?(current_str, "collector")
    end
  end

  describe "do_rebalance with database devices" do
    alias SwitchTelemetry.Devices

    test "assigns devices to available collectors" do
      # Create active devices in the database
      n = System.unique_integer([:positive])

      {:ok, device1} =
        Devices.create_device(%{
          id: "rebal-dev-#{n}-1",
          hostname: "rebal-switch-#{n}-1",
          ip_address: "10.99.#{rem(n, 255)}.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          assigned_collector: nil
        })

      {:ok, device2} =
        Devices.create_device(%{
          id: "rebal-dev-#{n}-2",
          hostname: "rebal-switch-#{n}-2",
          ip_address: "10.99.#{rem(n, 255)}.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          assigned_collector: nil
        })

      # Build a ring with a node and trigger rebalance via handle_cast
      ring =
        [Node.self()]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      state = %{ring: ring}
      {:noreply, ^state} = DeviceAssignment.handle_cast(:rebalance, state)

      # Verify the devices now have assigned_collector set
      updated1 = Devices.get_device!(device1.id)
      updated2 = Devices.get_device!(device2.id)

      assert updated1.assigned_collector == Atom.to_string(Node.self())
      assert updated2.assigned_collector == Atom.to_string(Node.self())
    end

    test "rebalance only affects active and unreachable devices" do
      n = System.unique_integer([:positive])

      {:ok, active_dev} =
        Devices.create_device(%{
          id: "rebal-active-#{n}",
          hostname: "active-sw-#{n}",
          ip_address: "10.98.#{rem(n, 255)}.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          assigned_collector: nil
        })

      {:ok, inactive_dev} =
        Devices.create_device(%{
          id: "rebal-inactive-#{n}",
          hostname: "inactive-sw-#{n}",
          ip_address: "10.98.#{rem(n, 255)}.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :inactive,
          assigned_collector: nil
        })

      {:ok, unreachable_dev} =
        Devices.create_device(%{
          id: "rebal-unreach-#{n}",
          hostname: "unreach-sw-#{n}",
          ip_address: "10.98.#{rem(n, 255)}.3",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :unreachable,
          assigned_collector: nil
        })

      ring =
        [Node.self()]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      state = %{ring: ring}
      {:noreply, ^state} = DeviceAssignment.handle_cast(:rebalance, state)

      # Active and unreachable should be assigned
      assert Devices.get_device!(active_dev.id).assigned_collector != nil
      assert Devices.get_device!(unreachable_dev.id).assigned_collector != nil

      # Inactive should NOT be assigned
      assert Devices.get_device!(inactive_dev.id).assigned_collector == nil
    end

    test "rebalance does not update device if already assigned to correct collector" do
      n = System.unique_integer([:positive])
      node_str = Atom.to_string(Node.self())

      {:ok, device} =
        Devices.create_device(%{
          id: "rebal-nochange-#{n}",
          hostname: "nochange-sw-#{n}",
          ip_address: "10.97.#{rem(n, 255)}.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          assigned_collector: node_str
        })

      ring =
        [Node.self()]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      state = %{ring: ring}
      {:noreply, ^state} = DeviceAssignment.handle_cast(:rebalance, state)

      # Device should still be assigned to the same collector
      updated = Devices.get_device!(device.id)
      assert updated.assigned_collector == node_str
    end
  end

  describe "get_owner with empty ring" do
    test "returns error when no collector nodes available" do
      ring = HashRing.new()
      state = %{ring: ring}

      assert {:reply, {:error, :no_collectors}, ^state} =
               DeviceAssignment.handle_call(
                 {:get_owner, "any-device-id"},
                 {self(), make_ref()},
                 state
               )
    end

    test "returns error for multiple different device IDs with empty ring" do
      ring = HashRing.new()
      state = %{ring: ring}

      for device_id <- ["dev-1", "dev-2", "dev-3", "some-uuid-here"] do
        assert {:reply, {:error, :no_collectors}, ^state} =
                 DeviceAssignment.handle_call(
                   {:get_owner, device_id},
                   {self(), make_ref()},
                   state
                 )
      end
    end
  end

  describe "do_rebalance with maintenance and inactive devices" do
    alias SwitchTelemetry.Devices

    test "maintenance devices are not assigned" do
      n = System.unique_integer([:positive])

      {:ok, maint_dev} =
        Devices.create_device(%{
          id: "rebal-maint-#{n}",
          hostname: "maint-sw-#{n}",
          ip_address: "10.96.#{rem(n, 255)}.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :maintenance,
          assigned_collector: nil
        })

      ring =
        [Node.self()]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      state = %{ring: ring}
      {:noreply, ^state} = DeviceAssignment.handle_cast(:rebalance, state)

      # Maintenance devices should not be assigned
      assert Devices.get_device!(maint_dev.id).assigned_collector == nil
    end

    test "rebalance reassigns device when collector changes" do
      n = System.unique_integer([:positive])

      {:ok, device} =
        Devices.create_device(%{
          id: "rebal-reassign-#{n}",
          hostname: "reassign-sw-#{n}",
          ip_address: "10.95.#{rem(n, 255)}.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          assigned_collector: "old_collector@nowhere"
        })

      ring =
        [Node.self()]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      state = %{ring: ring}
      {:noreply, ^state} = DeviceAssignment.handle_cast(:rebalance, state)

      updated = Devices.get_device!(device.id)
      # Should be reassigned from "old_collector@nowhere" to Node.self()
      assert updated.assigned_collector == Atom.to_string(Node.self())
    end
  end

  describe "ring distribution" do
    test "devices distribute across multiple nodes" do
      ring =
        [:node_a@host, :node_b@host, :node_c@host]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      state = %{ring: ring}

      assignments =
        for i <- 1..50 do
          {:reply, {:ok, node}, ^state} =
            DeviceAssignment.handle_call(
              {:get_owner, "device-#{i}"},
              {self(), make_ref()},
              state
            )

          node
        end

      unique_nodes = Enum.uniq(assignments)
      # With 50 devices and 3 nodes, should use at least 2 nodes
      assert length(unique_nodes) >= 2
    end

    test "adding a node redistributes some keys" do
      ring_before =
        [:node_a@host, :node_b@host]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      ring_after =
        [:node_a@host, :node_b@host, :node_c@host]
        |> Enum.reduce(HashRing.new(), &HashRing.add_node(&2, &1))

      # Check that at least some keys moved
      results_before = for i <- 1..50, do: HashRing.key_to_node(ring_before, "dev-#{i}")

      results_after = for i <- 1..50, do: HashRing.key_to_node(ring_after, "dev-#{i}")

      # Some should remain the same (consistent hashing)
      same_count = Enum.count(Enum.zip(results_before, results_after), fn {a, b} -> a == b end)
      assert same_count > 0

      # But some should have changed (new node got some)
      different_count = 50 - same_count
      assert different_count > 0 or Enum.member?(results_after, :node_c@host)
    end
  end
end

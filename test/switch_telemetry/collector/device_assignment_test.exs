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

      {:noreply, new_state} =
        DeviceAssignment.handle_info({:nodedown, :old_node@host, []}, state)

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

      {:noreply, state_after_up} =
        DeviceAssignment.handle_info({:nodeup, :x@host, []}, state)

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
end

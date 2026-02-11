defmodule SwitchTelemetry.Collector.DeviceAssignmentTest do
  use SwitchTelemetry.DataCase, async: true

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
end

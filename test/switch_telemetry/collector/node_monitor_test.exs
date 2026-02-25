defmodule SwitchTelemetry.Collector.NodeMonitorTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.NodeMonitor

  describe "module" do
    test "exports start_link/1" do
      assert function_exported?(NodeMonitor, :start_link, 1)
    end

    test "exports cluster_status/0" do
      assert function_exported?(NodeMonitor, :cluster_status, 0)
    end
  end

  describe "init/1" do
    test "initializes with self in nodes set" do
      {:ok, state} = NodeMonitor.init([])
      assert MapSet.member?(state.nodes, Node.self())
    end
  end

  describe "handle_call :cluster_status" do
    test "returns status map with current node info" do
      state = %{nodes: MapSet.new([Node.self()])}
      {:reply, status, ^state} = NodeMonitor.handle_call(:cluster_status, self(), state)

      assert status.self == Node.self()
      assert Node.self() in status.nodes
      assert status.node_count == 1
    end

    test "reflects multiple nodes" do
      nodes = MapSet.new([Node.self(), :other@host])
      {:reply, status, _} = NodeMonitor.handle_call(:cluster_status, self(), %{nodes: nodes})

      assert status.node_count == 2
      assert :other@host in status.nodes
    end
  end

  describe "handle_info {:nodeup, ...}" do
    test "adds new node to set" do
      state = %{nodes: MapSet.new([Node.self()])}
      {:noreply, new_state} = NodeMonitor.handle_info({:nodeup, :new@host, []}, state)

      assert MapSet.member?(new_state.nodes, :new@host)
      assert MapSet.size(new_state.nodes) == 2
    end

    test "is idempotent for existing node" do
      state = %{nodes: MapSet.new([Node.self(), :existing@host])}
      {:noreply, new_state} = NodeMonitor.handle_info({:nodeup, :existing@host, []}, state)

      assert MapSet.size(new_state.nodes) == 2
    end
  end

  describe "handle_info {:nodedown, ...}" do
    test "removes node from set" do
      state = %{nodes: MapSet.new([Node.self(), :leaving@host])}
      {:noreply, new_state} = NodeMonitor.handle_info({:nodedown, :leaving@host, []}, state)

      refute MapSet.member?(new_state.nodes, :leaving@host)
      assert MapSet.size(new_state.nodes) == 1
    end

    test "schedules rebalance" do
      state = %{nodes: MapSet.new([Node.self(), :down@host])}
      {:noreply, _} = NodeMonitor.handle_info({:nodedown, :down@host, []}, state)

      assert_receive :trigger_rebalance, 3_000
    end
  end

  describe "handle_info :trigger_rebalance" do
    test "survives when DeviceAssignment is not running" do
      state = %{nodes: MapSet.new([Node.self()])}
      assert {:noreply, ^state} = NodeMonitor.handle_info(:trigger_rebalance, state)
    end
  end

  describe "handle_info catchall" do
    test "ignores unknown messages" do
      state = %{nodes: MapSet.new()}
      assert {:noreply, ^state} = NodeMonitor.handle_info(:unknown, state)
    end
  end
end

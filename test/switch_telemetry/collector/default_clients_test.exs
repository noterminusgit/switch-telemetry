defmodule SwitchTelemetry.Collector.DefaultClientsTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Collector.DefaultGrpcClient
  alias SwitchTelemetry.Collector.DefaultSshClient

  setup_all do
    Code.ensure_loaded!(DefaultGrpcClient)
    Code.ensure_loaded!(DefaultSshClient)
    :ok
  end

  describe "DefaultGrpcClient" do
    test "implements GrpcClient behaviour" do
      behaviours =
        DefaultGrpcClient.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert SwitchTelemetry.Collector.GrpcClient in behaviours
    end

    test "exports connect/2" do
      assert function_exported?(DefaultGrpcClient, :connect, 2)
    end

    test "exports disconnect/1" do
      assert function_exported?(DefaultGrpcClient, :disconnect, 1)
    end

    test "exports subscribe/1" do
      assert function_exported?(DefaultGrpcClient, :subscribe, 1)
    end

    test "exports send_request/2" do
      assert function_exported?(DefaultGrpcClient, :send_request, 2)
    end

    test "exports recv/1" do
      assert function_exported?(DefaultGrpcClient, :recv, 1)
    end

    test "exports exactly 5 public functions" do
      functions = DefaultGrpcClient.__info__(:functions)
      assert length(functions) == 5

      assert {:connect, 2} in functions
      assert {:disconnect, 1} in functions
      assert {:subscribe, 1} in functions
      assert {:send_request, 2} in functions
      assert {:recv, 1} in functions
    end
  end

  describe "DefaultSshClient" do
    test "implements SshClient behaviour" do
      behaviours =
        DefaultSshClient.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert SwitchTelemetry.Collector.SshClient in behaviours
    end

    test "exports connect/3" do
      assert function_exported?(DefaultSshClient, :connect, 3)
    end

    test "exports session_channel/2" do
      assert function_exported?(DefaultSshClient, :session_channel, 2)
    end

    test "exports subsystem/4" do
      assert function_exported?(DefaultSshClient, :subsystem, 4)
    end

    test "exports send/3" do
      assert function_exported?(DefaultSshClient, :send, 3)
    end

    test "exports close/1" do
      assert function_exported?(DefaultSshClient, :close, 1)
    end

    test "exports exactly 5 public functions" do
      functions = DefaultSshClient.__info__(:functions)
      assert length(functions) == 5

      assert {:connect, 3} in functions
      assert {:session_channel, 2} in functions
      assert {:subsystem, 4} in functions
      assert {:send, 3} in functions
      assert {:close, 1} in functions
    end
  end
end

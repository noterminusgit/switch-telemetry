defmodule SwitchTelemetry.Collector.GrpcClient do
  @moduledoc "Behaviour wrapping gRPC client operations for gNMI sessions."

  @callback connect(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback disconnect(term()) :: {:ok, term()}
  @callback subscribe(term()) :: term()
  @callback send_request(term(), term()) :: term()
  @callback recv(term()) :: {:ok, Enumerable.t()} | {:error, term()}
  @callback capabilities(term(), term()) :: {:ok, term()} | {:error, term()}
  @callback capabilities(term(), term(), keyword()) :: {:ok, term()} | {:error, term()}
end

defmodule SwitchTelemetry.Collector.DefaultGrpcClient do
  @moduledoc false
  @behaviour SwitchTelemetry.Collector.GrpcClient

  @impl true
  def connect(target, opts), do: GRPC.Stub.connect(target, opts)

  @impl true
  def disconnect(channel), do: GRPC.Stub.disconnect(channel)

  @impl true
  def subscribe(channel), do: Gnmi.GNMI.Stub.subscribe(channel)

  @impl true
  def send_request(stream, request), do: GRPC.Stub.send_request(stream, request)

  @impl true
  def recv(stream), do: GRPC.Stub.recv(stream)

  @impl true
  def capabilities(channel, request), do: Gnmi.GNMI.Stub.capabilities(channel, request)

  @impl true
  def capabilities(channel, request, opts),
    do: Gnmi.GNMI.Stub.capabilities(channel, request, opts)
end

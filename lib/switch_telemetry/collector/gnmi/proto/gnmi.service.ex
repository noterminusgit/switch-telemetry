defmodule Gnmi.GNMI.Service do
  @moduledoc false
  use GRPC.Service, name: "gnmi.gNMI", protoc_gen_elixir_version: "0.14.0"

  rpc(:Subscribe, stream(Gnmi.SubscribeRequest), stream(Gnmi.SubscribeResponse))
end

defmodule Gnmi.GNMI.Stub do
  @moduledoc false
  use GRPC.Stub, service: Gnmi.GNMI.Service
end

defmodule Gnmi.PathElem.KeyEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Gnmi.PathElem do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :name, 1, type: :string
  field :key, 2, repeated: true, type: Gnmi.PathElem.KeyEntry, map: true
end

defmodule Gnmi.Path do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :elem, 1, repeated: true, type: Gnmi.PathElem
  field :origin, 2, type: :string
  field :target, 3, type: :string
end

defmodule Gnmi.TypedValue do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  oneof :value, 0

  field :string_val, 1, type: :string, oneof: 0
  field :int_val, 2, type: :int64, oneof: 0
  field :uint_val, 3, type: :uint64, oneof: 0
  field :bool_val, 4, type: :bool, oneof: 0
  field :bytes_val, 5, type: :bytes, oneof: 0
  field :float_val, 6, type: :float, oneof: 0
  field :double_val, 7, type: :double, oneof: 0
  field :json_val, 9, type: :bytes, oneof: 0
  field :json_ietf_val, 10, type: :bytes, oneof: 0
end

defmodule Gnmi.Update do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :path, 1, type: Gnmi.Path
  field :val, 6, type: Gnmi.TypedValue
  field :duplicates, 4, type: :uint32
end

defmodule Gnmi.Notification do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :timestamp, 1, type: :int64
  field :prefix, 2, type: Gnmi.Path
  field :update, 4, repeated: true, type: Gnmi.Update
  field :delete, 5, repeated: true, type: Gnmi.Path
  field :atomic, 6, type: :bool
end

defmodule Gnmi.QOS do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :marking, 1, type: :uint32
end

defmodule Gnmi.Encoding do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :JSON, 0
  field :BYTES, 1
  field :PROTO, 2
  field :ASCII, 3
  field :JSON_IETF, 4
end

defmodule Gnmi.SubscriptionMode do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :TARGET_DEFINED, 0
  field :ON_CHANGE, 1
  field :SAMPLE, 2
end

defmodule Gnmi.SubscriptionListMode do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :STREAM, 0
  field :ONCE, 1
  field :POLL, 2
end

defmodule Gnmi.Subscription do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :path, 1, type: Gnmi.Path
  field :mode, 2, type: Gnmi.SubscriptionMode, enum: true
  field :sample_interval, 3, type: :uint64
  field :suppress_redundant, 4, type: :bool
  field :heartbeat_interval, 5, type: :uint64
end

defmodule Gnmi.SubscriptionList do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  field :prefix, 1, type: Gnmi.Path
  field :subscription, 2, repeated: true, type: Gnmi.Subscription
  field :qos, 4, type: Gnmi.QOS
  field :mode, 5, type: Gnmi.SubscriptionListMode, enum: true
  field :encoding, 6, type: Gnmi.Encoding, enum: true
  field :updates_only, 9, type: :bool
end

defmodule Gnmi.Poll do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"
end

defmodule Gnmi.SubscribeRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  oneof :request, 0

  field :subscribe, 1, type: Gnmi.SubscriptionList, oneof: 0
  field :poll, 3, type: Gnmi.Poll, oneof: 0
end

defmodule Gnmi.SubscribeResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.14.0"

  oneof :response, 0

  field :update, 1, type: Gnmi.Notification, oneof: 0
  field :sync_response, 3, type: :bool, oneof: 0
end

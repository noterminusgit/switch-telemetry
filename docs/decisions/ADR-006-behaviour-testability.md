# ADR-006: Behaviour Abstractions for Protocol Testability

**Status:** Accepted
**Date:** 2026-02-15
**Deciders:** Engineering team
**Context:** GnmiSession and NetconfSession made direct calls to `GRPC.Stub` and `:ssh` modules, making them impossible to unit test without real network connections

## Context

`GnmiSession` originally called `GRPC.Stub.connect/2`, `GRPC.Stub.disconnect/1`, `GRPC.Stub.send_request/2`, `GRPC.Stub.recv/1`, and `Gnmi.GNMI.Stub.subscribe/1` directly. `NetconfSession` originally called `:ssh.connect/3`, `:ssh_connection.session_channel/2`, `:ssh_connection.subsystem/4`, `:ssh_connection.send/3`, and `:ssh.close/1` directly. This made it impossible to unit-test GenServer lifecycle callbacks (`init`, `handle_info`, `handle_continue`, `terminate`) in isolation without establishing real gRPC channels or SSH connections.

Testing required either:
1. Running real network devices or simulators (impractical in CI)
2. Skipping tests for all connection logic (unacceptable coverage gap)

This prevented testing GenServer lifecycle callbacks in isolation -- for example, verifying that `handle_info(:connect, state)` correctly updates device status on failure, or that `terminate/2` properly disconnects gRPC channels and closes SSH connections.

## Decision

Introduce `GrpcClient` and `SshClient` behaviour modules that define the external call interfaces. Wrap all external gRPC and SSH calls behind behaviour dispatch using `Application.get_env(:switch_telemetry, :grpc_client)` and `Application.get_env(:switch_telemetry, :ssh_client)`. Production code uses `DefaultGrpcClient` and `DefaultSshClient`; tests use Mox mocks.

## Alternatives Considered

### Alternative 1: Starting Real gRPC/SSH Servers in Tests

**Pros:**
- Tests exercise the real protocol stack end-to-end
- No abstraction layer needed

**Cons:**
- Fragile: tests depend on network stack, port availability, timing
- Slow: TCP handshakes, SSH key exchange, gRPC channel setup
- Requires external services running in CI (gNMI target, SSH server)

**Why Rejected:** Fragile, slow, requires external services running in CI.

### Alternative 2: Module-Level Mocking via `:meck`

**Pros:**
- No code changes to production modules
- Can mock any module at runtime

**Cons:**
- Not idiomatic Elixir; `:meck` replaces module bytecode at runtime
- No compile-time contract checking (mocked functions can drift from real API)
- Harder to maintain and reason about
- Can interfere with other tests in the same BEAM instance

**Why Rejected:** Not idiomatic Elixir, no compile-time contract checking, harder to maintain.

### Alternative 3: Passing Module as GenServer Init Arg

**Pros:**
- Explicit dependency injection, no global state
- Each process can use a different implementation

**Cons:**
- Requires changing the GenServer struct and all call sites
- Inconsistent with Phoenix conventions (which use Application config)
- More boilerplate in `start_link/1` and `init/1`

**Why Rejected:** Considered but `Application.get_env` is simpler and consistent with Phoenix conventions and the existing `Metrics.Backend` pattern (ADR-005).

## Implementation

### GrpcClient Behaviour

Defined in `lib/switch_telemetry/collector/grpc_client.ex`:

```elixir
defmodule SwitchTelemetry.Collector.GrpcClient do
  @moduledoc "Behaviour wrapping gRPC client operations for gNMI sessions."

  @callback connect(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback disconnect(term()) :: {:ok, term()}
  @callback subscribe(term()) :: term()
  @callback send_request(term(), term()) :: term()
  @callback recv(term()) :: {:ok, Enumerable.t()} | {:error, term()}
end
```

### DefaultGrpcClient

Defined alongside the behaviour in the same file:

```elixir
defmodule SwitchTelemetry.Collector.DefaultGrpcClient do
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
end
```

### SshClient Behaviour

Defined in `lib/switch_telemetry/collector/ssh_client.ex`:

```elixir
defmodule SwitchTelemetry.Collector.SshClient do
  @moduledoc "Behaviour wrapping SSH client operations for NETCONF sessions."

  @callback connect(charlist(), integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  @callback session_channel(pid(), integer()) :: {:ok, integer()} | {:error, term()}
  @callback subsystem(pid(), integer(), charlist(), integer()) :: :success | :failure
  @callback send(pid(), integer(), iodata()) :: :ok | {:error, term()}
  @callback close(pid()) :: :ok
end
```

### DefaultSshClient

Defined alongside the behaviour in the same file:

```elixir
defmodule SwitchTelemetry.Collector.DefaultSshClient do
  @behaviour SwitchTelemetry.Collector.SshClient

  @impl true
  def connect(host, port, opts), do: :ssh.connect(host, port, opts)

  @impl true
  def session_channel(ssh_ref, timeout), do: :ssh_connection.session_channel(ssh_ref, timeout)

  @impl true
  def subsystem(ssh_ref, channel_id, subsystem, timeout),
    do: :ssh_connection.subsystem(ssh_ref, channel_id, subsystem, timeout)

  @impl true
  def send(ssh_ref, channel_id, data), do: :ssh_connection.send(ssh_ref, channel_id, data)

  @impl true
  def close(ssh_ref), do: :ssh.close(ssh_ref)
end
```

### Dispatch Pattern

Each session GenServer reads the active implementation from application config via a private helper function, defaulting to the real implementation:

```elixir
# In GnmiSession
defp grpc_client do
  Application.get_env(
    :switch_telemetry,
    :grpc_client,
    SwitchTelemetry.Collector.DefaultGrpcClient
  )
end

# In NetconfSession
defp ssh_client do
  Application.get_env(
    :switch_telemetry,
    :ssh_client,
    SwitchTelemetry.Collector.DefaultSshClient
  )
end
```

The GenServer callbacks then call through the dispatch helper. For example, in `GnmiSession.handle_info(:connect, state)`:

```elixir
case grpc_client().connect(target, []) do
  {:ok, channel} -> ...
  {:error, reason} -> ...
end
```

And in `GnmiSession.terminate/2`:

```elixir
def terminate(_reason, state) do
  if state.channel do
    grpc_client().disconnect(state.channel)
  end
  :ok
end
```

### Test Configuration

Mox mocks are defined in `test/support/mocks.ex`:

```elixir
Mox.defmock(SwitchTelemetry.Collector.MockGrpcClient,
  for: SwitchTelemetry.Collector.GrpcClient)
Mox.defmock(SwitchTelemetry.Collector.MockSshClient,
  for: SwitchTelemetry.Collector.SshClient)
```

In test setup blocks, the mock is installed via `Application.put_env` and cleaned up on exit:

```elixir
Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)
on_exit(fn -> Application.delete_env(:switch_telemetry, :grpc_client) end)
```

## Consequences

### Positive
1. +44 lifecycle tests covering GenServer callbacks for GnmiSession, NetconfSession, and NodeMonitor
2. GenServer callbacks now fully testable in isolation without network access
3. Tests run in milliseconds (no TCP/SSH handshakes, no gRPC channel setup)
4. CI does not require network device simulators or real gNMI/NETCONF targets
5. No behaviour change in production (`DefaultGrpcClient` and `DefaultSshClient` delegate to the original modules with zero logic)
6. Mox verifies that all expected calls were made (`verify_on_exit!`) and provides compile-time contract checking against the behaviour
7. Consistent with the `Metrics.Backend` behaviour pattern already established in the codebase (ADR-005)

### Negative
1. One extra layer of indirection for external calls
2. Behaviour callbacks must be updated if the underlying library API changes (e.g., `GRPC.Stub` or `:ssh` interface changes)
3. Small runtime overhead of `Application.get_env` lookup (negligible -- single ETS read per call)
4. `Application.get_env/3` is a global lookup (not process-isolated); tests using these mocks must run with `async: false`

### Mitigations
- Behaviours are minimal (5 callbacks each), so maintenance burden is low
- `DefaultGrpcClient` and `DefaultSshClient` are thin wrappers with no logic, reducing the chance of bugs in the indirection layer
- `async: false` is already required for these tests due to database interaction and PubSub side effects
- Pattern can be reused for future external service abstractions (e.g., if additional protocol clients are added)

## Related ADRs
- ADR-004: Custom Protocol Clients for gNMI and NETCONF
- ADR-005: InfluxDB Migration (established the Backend behaviour pattern)

## Review Schedule
**Last Reviewed:** 2026-02-15
**Next Review:** 2026-08-15

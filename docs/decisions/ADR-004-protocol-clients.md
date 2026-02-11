# ADR-004: Custom Protocol Clients for gNMI and NETCONF

**Status:** Accepted
**Date:** 2026-02-10

## Context

We need to connect to network devices using two protocols:
- **gNMI** (gRPC-based, streaming telemetry)
- **NETCONF** (SSH-based, XML RPC)

No turnkey Elixir libraries exist for either protocol in the network management domain.

## Decision

### gNMI
Use `elixir-grpc/grpc` (v0.11+) as the gRPC framework. Compile OpenConfig's `gnmi.proto` with `protobuf` to generate Elixir client stubs. Wrap the generated `Gnmi.GNMI.Stub.subscribe/2` in a GenServer that manages the bidirectional stream lifecycle.

### NETCONF
Build a custom NETCONF client using Erlang's `:ssh` application. Use `:ssh.connect/3` + `:ssh_connection.subsystem/4` to invoke the `netconf` subsystem on port 830. Parse XML responses with `SweetXml` (XPath queries).

## Rationale

### gNMI
- `grpc` hex package has 4.9M+ total downloads, is actively maintained, and supports bidirectional streaming
- The gNMI proto is well-defined by OpenConfig; code generation produces type-safe Elixir structs
- Streaming via `GRPC.Stub.send_request/2` and `GRPC.Stub.recv/1` maps naturally to a GenServer + Task pattern

### NETCONF
- Erlang's `:ssh` module is battle-tested (part of OTP) and supports SSH subsystem invocation natively
- `ct_netconfc` (Erlang's built-in NETCONF client) is tightly coupled to Common Test and not designed for production use
- No other maintained NETCONF library exists for Elixir/Erlang
- SweetXml provides ergonomic XPath querying (`~x"//interface/name/text()"s`) which is perfect for navigating NETCONF XML responses
- Building our own client gives us full control over connection pooling, reconnection, and error handling

## Consequences

### Positive
- Full control over connection lifecycle and error handling
- Type-safe gNMI messages via protobuf code generation
- No dependency on unmaintained third-party network libraries
- Can support vendor-specific YANG model quirks

### Negative
- More upfront development effort than using a turnkey library
- Must handle NETCONF framing (RFC 6242 chunked framing) ourselves
- Must handle gNMI path encoding/decoding for different vendor implementations
- Need to test against real devices from each vendor (Cisco, Juniper, Arista, Nokia)

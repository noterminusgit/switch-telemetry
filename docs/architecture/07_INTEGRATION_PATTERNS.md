# 07: Integration Patterns

## HTTP Client (Finch)

External HTTP calls (webhooks, REST APIs for device management platforms, notification services) use Finch with retry and circuit breaker patterns.

### Finch Setup

```elixir
# In application supervision tree
children = [
  {Finch, name: SwitchTelemetry.Finch, pools: %{default: [size: 25, count: 4]}}
]
```

### Request with Retry and Backoff

```elixir
defmodule SwitchTelemetry.Integration.HTTPClient do
  @moduledoc """
  HTTP client wrapper with exponential backoff retry.
  All external HTTP calls go through this module.
  """

  @default_timeout 5_000
  @default_retries 3

  def get(url, opts \\ []) do
    request(:get, url, nil, opts)
  end

  def post(url, body, opts \\ []) do
    request(:post, url, body, opts)
  end

  defp request(method, url, body, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)
    headers = Keyword.get(opts, :headers, [{"content-type", "application/json"}])

    req =
      Finch.build(method, url, headers, encode_body(body))

    do_request(req, timeout, retries, _attempt = 1)
  end

  defp do_request(req, timeout, retries_left, attempt) do
    case Finch.request(req, SwitchTelemetry.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{status: status}} when status in 500..599 and retries_left > 0 ->
        backoff = calculate_backoff(attempt)
        Process.sleep(backoff)
        do_request(req, timeout, retries_left - 1, attempt + 1)

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} when retries_left > 0 ->
        backoff = calculate_backoff(attempt)
        Process.sleep(backoff)
        do_request(req, timeout, retries_left - 1, attempt + 1)

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  defp calculate_backoff(attempt) do
    # Exponential backoff: 100ms, 200ms, 400ms, 800ms...
    base = trunc(:math.pow(2, attempt - 1) * 100)
    # Add jitter (0-50% of base)
    jitter = :rand.uniform(div(base, 2) + 1)
    base + jitter
  end

  defp encode_body(nil), do: nil
  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body), do: Jason.encode!(body)
end
```

## Circuit Breaker

For external services that may go down, wrap calls in a circuit breaker to fail fast and avoid cascading failures.

```elixir
defmodule SwitchTelemetry.Integration.CircuitBreaker do
  @moduledoc """
  Simple circuit breaker implemented as a GenServer.
  States: :closed (normal), :open (failing fast), :half_open (testing recovery).
  """
  use GenServer

  @failure_threshold 5
  @reset_timeout :timer.seconds(30)

  defstruct state: :closed, failure_count: 0, last_failure: nil

  def start_link(name) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: name)
  end

  def call(breaker, fun) do
    case GenServer.call(breaker, :check_state) do
      :ok ->
        try do
          result = fun.()
          GenServer.cast(breaker, :record_success)
          result
        rescue
          e ->
            GenServer.cast(breaker, :record_failure)
            {:error, {:circuit_breaker, :call_failed, e}}
        end

      :open ->
        {:error, {:circuit_breaker, :open}}
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:check_state, _from, %{state: :open} = s) do
    if System.monotonic_time(:millisecond) - s.last_failure > @reset_timeout do
      {:reply, :ok, %{s | state: :half_open}}
    else
      {:reply, :open, s}
    end
  end

  def handle_call(:check_state, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:record_success, state) do
    {:noreply, %{state | state: :closed, failure_count: 0}}
  end

  def handle_cast(:record_failure, state) do
    new_count = state.failure_count + 1
    new_state = if new_count >= @failure_threshold, do: :open, else: state.state

    {:noreply, %{state |
      state: new_state,
      failure_count: new_count,
      last_failure: System.monotonic_time(:millisecond)
    }}
  end
end
```

## Webhook Handling

### Incoming Webhooks (Device Events from External NMS)

```elixir
defmodule SwitchTelemetryWeb.WebhookController do
  use SwitchTelemetryWeb, :controller

  def receive(conn, %{"event" => event_type} = params) do
    case validate_webhook(conn) do
      :ok ->
        # Enqueue processing as a background job
        %{event_type: event_type, payload: params}
        |> SwitchTelemetry.Workers.WebhookProcessor.new()
        |> Oban.insert()

        conn |> put_status(202) |> json(%{status: "accepted"})

      {:error, :invalid_signature} ->
        conn |> put_status(401) |> json(%{error: "invalid signature"})
    end
  end

  defp validate_webhook(conn) do
    # Verify HMAC signature from request headers
    signature = get_req_header(conn, "x-webhook-signature") |> List.first()
    body = conn.assigns[:raw_body]
    secret = Application.fetch_env!(:switch_telemetry, :webhook_secret)

    expected = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, signature || ""), do: :ok, else: {:error, :invalid_signature}
  end
end
```

### Outgoing Webhooks (Alert Notifications)

```elixir
defmodule SwitchTelemetry.Workers.WebhookNotifier do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    priority: 2

  alias SwitchTelemetry.Integration.HTTPClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"url" => url, "event" => event, "payload" => payload}}) do
    body = %{
      event: event,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: payload
    }

    case HTTPClient.post(url, body, retries: 0) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}  # Oban retries with backoff
    end
  end
end
```

## Oban Worker Patterns

All external calls are routed through Oban workers to keep the request path non-blocking.

### Queue Configuration

```elixir
# config/config.exs
config :switch_telemetry, Oban,
  repo: SwitchTelemetry.Repo,
  queues: [
    default: 10,
    discovery: 5,
    notifications: 10,
    maintenance: 3
  ]
```

### Discovery Worker

```elixir
defmodule SwitchTelemetry.Workers.DeviceDiscovery do
  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3,
    unique: [period: 300]  # Deduplicate within 5 minutes

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subnet" => subnet}}) do
    subnet
    |> scan_network()
    |> Enum.each(fn ip ->
      case identify_device(ip) do
        {:ok, device_info} ->
          SwitchTelemetry.Devices.upsert_device(device_info)

        {:error, :unreachable} ->
          :skip
      end
    end)

    :ok
  end
end
```

### Stale Session Cleanup

```elixir
defmodule SwitchTelemetry.Workers.SessionCleanup do
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    stale_threshold = DateTime.add(DateTime.utc_now(), -300, :second)

    SwitchTelemetry.Collector.DeviceManager.get_stale_sessions(stale_threshold)
    |> Enum.each(fn session ->
      SwitchTelemetry.Collector.DeviceManager.restart_session(session.device_id)
    end)

    :ok
  end
end
```

## External Service Timeouts

All external calls must have explicit timeouts. Never use `:infinity`.

```elixir
# gRPC channel options
{:ok, channel} = GRPC.Stub.connect(host, port,
  interceptors: [],
  adapter_opts: %{
    http2_opts: %{keepalive: 60_000},
    connect_timeout: 5_000
  }
)

# SSH connection options
ssh_opts = [
  connect_timeout: 10_000,
  idle_time: 300_000,
  silently_accept_hosts: true
]

# Finch HTTP requests
Finch.request(req, SwitchTelemetry.Finch, receive_timeout: 5_000)
```

## Error Classification

Classify errors to determine retry strategy:

```elixir
defmodule SwitchTelemetry.Integration.ErrorClassifier do
  @doc "Classify an error as retryable or permanent."
  def classify({:error, :timeout}), do: :retryable
  def classify({:error, :econnrefused}), do: :retryable
  def classify({:error, {:http_error, status, _}}) when status in 500..599, do: :retryable
  def classify({:error, {:http_error, 429, _}}), do: :retryable  # Rate limited
  def classify({:error, {:http_error, status, _}}) when status in 400..499, do: :permanent
  def classify({:error, :invalid_credentials}), do: :permanent
  def classify({:error, _}), do: :unknown
end
```

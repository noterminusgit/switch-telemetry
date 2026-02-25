defmodule SwitchTelemetry.InfluxCase do
  @moduledoc """
  Test case template for tests that interact with InfluxDB.
  Clears the test bucket before each test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :influx

      alias SwitchTelemetry.InfluxDB
      alias SwitchTelemetry.Metrics

      import SwitchTelemetry.InfluxCase, only: [eventually: 1, eventually: 2]
    end
  end

  @doc """
  Polls `fun` every 100ms for up to `timeout_ms` (default 2000) until it returns
  a truthy value. Raises on timeout. Replaces brittle `Process.sleep` in
  read-after-write InfluxDB tests.
  """
  def eventually(fun, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_eventually(fun, deadline)
  end

  defp do_eventually(fun, deadline) do
    case fun.() do
      nil -> maybe_retry(fun, deadline)
      false -> maybe_retry(fun, deadline)
      [] -> maybe_retry(fun, deadline)
      result -> result
    end
  end

  defp maybe_retry(fun, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      raise "eventually/2 timed out"
    else
      Process.sleep(100)
      do_eventually(fun, deadline)
    end
  end

  setup _tags do
    clear_influx_bucket()
    # Small delay to ensure InfluxDB has processed the delete
    Process.sleep(50)
    :ok
  end

  defp clear_influx_bucket do
    config = Application.get_env(:switch_telemetry, SwitchTelemetry.InfluxDB)
    bucket = Keyword.fetch!(config, :bucket)
    org = Keyword.fetch!(config, :org)
    scheme = Keyword.get(config, :scheme, "http")
    host = Keyword.fetch!(config, :host)
    port = Keyword.fetch!(config, :port)
    auth = Keyword.fetch!(config, :auth)
    token = Keyword.fetch!(auth, :token)

    url =
      "#{scheme}://#{host}:#{port}/api/v2/delete?org=#{URI.encode_www_form(org)}&bucket=#{URI.encode_www_form(bucket)}"

    body =
      Jason.encode!(%{
        start: "1970-01-01T00:00:00Z",
        stop: "2100-01-01T00:00:00Z"
      })

    # Use Finch to make the delete request
    Finch.build(
      :post,
      url,
      [{"Authorization", "Token #{token}"}, {"Content-Type", "application/json"}],
      body
    )
    |> Finch.request(SwitchTelemetry.Finch)
  end
end

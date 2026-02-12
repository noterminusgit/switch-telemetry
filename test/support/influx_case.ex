defmodule SwitchTelemetry.InfluxCase do
  @moduledoc """
  Test case template for tests that interact with InfluxDB.
  Clears the test bucket before each test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias SwitchTelemetry.InfluxDB
      alias SwitchTelemetry.Metrics
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

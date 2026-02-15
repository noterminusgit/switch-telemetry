# Dialyzer Configuration

Static type analysis setup for Switch Telemetry.

## Dependency

In `mix.exs`:

```elixir
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

## Project Config

In `mix.exs` project definition:

```elixir
dialyzer: [
  plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
  plt_add_apps: [:mix, :ex_unit],
  flags: [:error_handling, :underspecs]
]
```

### Flag Meanings

| Flag | Purpose |
|------|---------|
| `:error_handling` | Warns about functions that only return by raising exceptions or have unmatched error paths |
| `:underspecs` | Warns when a `@spec` is more restrictive than what the function actually accepts/returns |

### PLT File

The PLT (Persistent Lookup Table) is stored at `priv/plts/dialyzer.plt`. The `{:no_warn, path}` tuple suppresses the "PLT is for a different version of OTP" warning during rebuilds.

## Running Locally

```bash
mkdir -p priv/plts
mix dialyzer
```

First run builds the PLT from scratch (slow, 5-15 minutes). Subsequent runs are incremental.

## CI Setup

From `.github/workflows/ci.yml`:

```yaml
- name: Restore PLT cache
  uses: actions/cache@v4
  with:
    path: priv/plts
    key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}
    restore-keys: |
      ${{ runner.os }}-plt-

- name: Create PLT directory
  run: mkdir -p priv/plts

- name: Run Dialyzer
  run: mix dialyzer
```

The PLT is cached by `mix.lock` hash. When dependencies change, the cache misses and PLT rebuilds with new deps included.

## Suppressing Warnings

If a file `.dialyzer_ignore.exs` exists in the project root, Dialyxir reads it for warnings to suppress. Currently no such file exists -- all warnings must be resolved.

To create one if needed:

```elixir
# .dialyzer_ignore.exs
[
  # {module, function, arity} or string patterns
  ~r/some_pattern_to_ignore/
]
```

## Adding Typespecs

### Functions

Add `@spec` before `def`:

```elixir
@spec get_device(String.t()) :: {:ok, Device.t()} | {:error, :not_found}
def get_device(id) do
  # ...
end
```

### Schemas

Add `@type t` before the `schema` block. All schemas in this project already follow this pattern:

```elixir
defmodule SwitchTelemetry.Devices.Device do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "devices" do
    field :hostname, :string
    # ...
  end
end
```

Schemas with `@type t :: %__MODULE__{}` already defined:
- `Devices.Device`, `Devices.Credential`
- `Dashboards.Dashboard`, `Dashboards.Widget`
- `Alerting.AlertRule`, `Alerting.AlertEvent`, `Alerting.NotificationChannel`, `Alerting.AlertChannelBinding`
- `Accounts.User`, `Accounts.UserToken`, `Accounts.AdminEmail`
- `Collector.Subscription`, `Collector.StreamMonitor`

### Callbacks

Use `@callback` in behaviour modules:

```elixir
defmodule SwitchTelemetry.Metrics.Backend do
  @callback insert_batch(list(map())) :: {non_neg_integer(), any()}
  @callback get_latest(String.t(), keyword()) :: list(map())
  @callback query(String.t(), map(), keyword()) :: list(map())
  @callback query_raw(String.t(), String.t(), DateTime.t(), DateTime.t()) :: list(map())
  @callback query_rate(String.t(), String.t(), DateTime.t(), DateTime.t()) :: list(map())
end
```

## Common Dialyzer Issues

| Issue | Fix |
|-------|-----|
| "Function has no local return" | The function always raises or pattern match is exhaustive but Dialyzer cannot prove it. Add a typespec or handle the missing clause. |
| "The pattern can never match" | Dead code. Remove the clause or fix the logic. |
| "Contract is a supertype" | The `@spec` is broader than what the function returns. Narrow the spec. |
| "Underspecified" (`:underspecs` flag) | The `@spec` is too narrow. Broaden it to match actual behavior. |

defmodule SwitchTelemetry.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: SwitchTelemetry.Vault
end

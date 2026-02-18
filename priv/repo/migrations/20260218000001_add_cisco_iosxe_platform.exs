defmodule SwitchTelemetry.Repo.Migrations.AddCiscoIosxePlatform do
  use Ecto.Migration

  def change do
    # No schema change needed — platform is stored as a string column
    # and Ecto.Enum handles the mapping in the application layer.
    # This migration exists as a documentation checkpoint for the
    # addition of :cisco_iosxe to the Device platform enum.
  end
end

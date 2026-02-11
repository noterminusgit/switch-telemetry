defmodule SwitchTelemetryWeb.Layouts do
  @moduledoc """
  Layout components for the web interface.
  """
  use SwitchTelemetryWeb, :html

  import SwitchTelemetryWeb.CoreComponents

  embed_templates "layouts/*"
end

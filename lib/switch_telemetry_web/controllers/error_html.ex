defmodule SwitchTelemetryWeb.ErrorHTML do
  @moduledoc """
  Error HTML templates.
  """
  use SwitchTelemetryWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

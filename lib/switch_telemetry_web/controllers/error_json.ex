defmodule SwitchTelemetryWeb.ErrorJSON do
  @moduledoc """
  Error JSON templates.
  """
  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

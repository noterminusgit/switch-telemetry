defmodule SwitchTelemetryWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetryWeb.ErrorJSON

  describe "render/2" do
    test "renders 404.json with Not Found detail" do
      result = ErrorJSON.render("404.json", %{})
      assert result == %{errors: %{detail: "Not Found"}}
    end

    test "renders 500.json with Internal Server Error detail" do
      result = ErrorJSON.render("500.json", %{})
      assert result == %{errors: %{detail: "Internal Server Error"}}
    end

    test "renders 403.json with Forbidden detail" do
      result = ErrorJSON.render("403.json", %{})
      assert result == %{errors: %{detail: "Forbidden"}}
    end

    test "renders 422.json with Unprocessable Content detail" do
      result = ErrorJSON.render("422.json", %{})
      assert result == %{errors: %{detail: "Unprocessable Content"}}
    end

    test "ignores assigns" do
      result = ErrorJSON.render("404.json", %{reason: "test", conn: nil})
      assert result == %{errors: %{detail: "Not Found"}}
    end
  end
end

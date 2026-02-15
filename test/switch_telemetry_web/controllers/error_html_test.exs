defmodule SwitchTelemetryWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetryWeb.ErrorHTML

  describe "render/2" do
    test "renders 404.html with Not Found message" do
      result = ErrorHTML.render("404.html", %{})
      assert result == "Not Found"
    end

    test "renders 500.html with Internal Server Error message" do
      result = ErrorHTML.render("500.html", %{})
      assert result == "Internal Server Error"
    end

    test "renders 403.html with Forbidden message" do
      result = ErrorHTML.render("403.html", %{})
      assert result == "Forbidden"
    end

    test "renders arbitrary status template" do
      result = ErrorHTML.render("422.html", %{})
      assert result == "Unprocessable Content"
    end

    test "ignores assigns" do
      result = ErrorHTML.render("404.html", %{reason: "test", conn: nil})
      assert result == "Not Found"
    end
  end
end

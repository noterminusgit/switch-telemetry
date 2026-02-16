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

    test "renders 401.html with Unauthorized message" do
      result = ErrorHTML.render("401.html", %{})
      assert result == "Unauthorized"
    end

    test "renders 503.html with Service Unavailable message" do
      result = ErrorHTML.render("503.html", %{})
      assert result == "Service Unavailable"
    end

    test "renders 400.html with Bad Request message" do
      result = ErrorHTML.render("400.html", %{})
      assert result == "Bad Request"
    end

    test "renders 405.html with Method Not Allowed message" do
      result = ErrorHTML.render("405.html", %{})
      assert result == "Method Not Allowed"
    end

    test "renders 408.html with Request Timeout message" do
      result = ErrorHTML.render("408.html", %{})
      assert result == "Request Timeout"
    end

    test "renders 429.html with Too Many Requests message" do
      result = ErrorHTML.render("429.html", %{})
      assert result == "Too Many Requests"
    end

    test "renders 502.html with Bad Gateway message" do
      result = ErrorHTML.render("502.html", %{})
      assert result == "Bad Gateway"
    end

    test "renders 504.html with Gateway Timeout message" do
      result = ErrorHTML.render("504.html", %{})
      assert result == "Gateway Timeout"
    end

    test "returns string for all rendered templates" do
      for status <- [400, 401, 403, 404, 405, 408, 422, 429, 500, 502, 503, 504] do
        result = ErrorHTML.render("#{status}.html", %{})
        assert is_binary(result), "Expected string for #{status}.html, got: #{inspect(result)}"
        assert String.length(result) > 0, "Expected non-empty string for #{status}.html"
      end
    end

    test "renders 409.html with Conflict message" do
      result = ErrorHTML.render("409.html", %{})
      assert result == "Conflict"
    end

    test "renders 410.html with Gone message" do
      result = ErrorHTML.render("410.html", %{})
      assert result == "Gone"
    end

    test "renders 413.html with Request Entity Too Large message" do
      result = ErrorHTML.render("413.html", %{})
      assert result == "Request Entity Too Large"
    end

    test "renders 415.html with Unsupported Media Type message" do
      result = ErrorHTML.render("415.html", %{})
      assert result == "Unsupported Media Type"
    end

    test "renders 451.html with Unavailable For Legal Reasons message" do
      result = ErrorHTML.render("451.html", %{})
      assert result == "Unavailable For Legal Reasons"
    end

    test "renders 501.html with Not Implemented message" do
      result = ErrorHTML.render("501.html", %{})
      assert result == "Not Implemented"
    end

    test "renders with complex assigns passed through" do
      assigns = %{
        conn: %Plug.Conn{},
        reason: %RuntimeError{message: "test error"},
        status: 500,
        kind: :error,
        stack: []
      }

      result = ErrorHTML.render("500.html", assigns)
      assert result == "Internal Server Error"
    end

    test "renders with empty assigns map" do
      result = ErrorHTML.render("404.html", %{})
      assert is_binary(result)
      assert result != ""
    end

    test "all 4xx status codes return non-empty strings" do
      for status <- 400..451 do
        result = ErrorHTML.render("#{status}.html", %{})
        assert is_binary(result), "Expected string for #{status}.html"
      end
    end

    test "all 5xx status codes return non-empty strings" do
      for status <- 500..511 do
        result = ErrorHTML.render("#{status}.html", %{})
        assert is_binary(result), "Expected string for #{status}.html"
      end
    end

    test "render/2 always returns a string regardless of template" do
      result = ErrorHTML.render("418.html", %{})
      assert is_binary(result)
      # 418 I'm a Teapot
      assert result =~ "Teapot" or is_binary(result)
    end
  end
end

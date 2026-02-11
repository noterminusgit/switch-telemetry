defmodule SwitchTelemetryWeb.Security.HeadersTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  test "CSP header is present on public pages", %{conn: conn} do
    conn = get(conn, ~p"/")
    csp = Plug.Conn.get_resp_header(conn, "content-security-policy")
    assert [csp_value] = csp
    assert csp_value =~ "default-src 'self'"
    assert csp_value =~ "script-src 'self' 'unsafe-eval'"
    assert csp_value =~ "frame-ancestors 'none'"
  end

  test "CSP header is present on login page", %{conn: conn} do
    conn = get(conn, ~p"/users/log_in")
    csp = Plug.Conn.get_resp_header(conn, "content-security-policy")
    assert [_csp_value] = csp
  end

  test "frame-ancestors directive prevents clickjacking", %{conn: conn} do
    conn = get(conn, ~p"/")
    [csp_value] = Plug.Conn.get_resp_header(conn, "content-security-policy")
    assert csp_value =~ "frame-ancestors 'none'"
  end

  test "X-Content-Type-Options header is present", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert Plug.Conn.get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end
end

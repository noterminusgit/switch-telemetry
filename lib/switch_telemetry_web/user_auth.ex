defmodule SwitchTelemetryWeb.UserAuth do
  @moduledoc """
  Plug functions and LiveView on_mount hooks for authentication
  and authorization in the SwitchTelemetry web interface.

  ## Plug functions (for router pipelines)

    * `fetch_current_user/2` - Fetches the current user from session or remember-me cookie
    * `redirect_if_user_is_authenticated/2` - Redirects to signed-in path if already logged in
    * `require_authenticated_user/2` - Requires a logged-in user, redirects to login otherwise
    * `require_admin/2` - Requires the current user to have the `:admin` role

  ## LiveView on_mount hooks

    * `:mount_current_user` - Assigns `current_user` to the socket
    * `:ensure_authenticated` - Halts if no user is authenticated
    * `:ensure_admin` - Halts if the user is not an admin
  """

  use SwitchTelemetryWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias SwitchTelemetry.Accounts

  # How many days to keep the "remember me" cookie valid
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_switch_telemetry_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax", http_only: true]

  @doc """
  Logs the user in by creating a session token.

  It renews the session ID and clears the whole session to avoid
  fixation attacks. The `user_return_to` value from the session
  is used to redirect the user after login, falling back to the
  signed-in path.

  ## Options

  The optional `params` map may include a `"remember_me"` key set
  to `"true"` to persist a signed cookie for extended sessions.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params), do: conn

  defp renew_session(conn) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  Deletes the session token from the database, broadcasts a disconnect
  to any connected LiveView sockets, clears the session, removes the
  remember-me cookie, and redirects to the login page.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      SwitchTelemetryWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/users/log_in")
  end

  @doc """
  Plug: Fetches the current user from the session.

  Checks the session for a `user_token` first. If not present, falls
  back to the signed remember-me cookie. Assigns `:current_user` to
  the conn (either a `%User{}` or `nil`). Also assigns `:current_path`
  for layout navigation highlighting.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)

    conn
    |> assign(:current_user, user)
    |> assign(:current_path, conn.request_path)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Plug: Redirects if user is already authenticated.

  Used on login/registration pages to bounce authenticated users
  back to the signed-in path.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Plug: Requires authenticated user.

  If no current user is assigned, stores the current path for
  post-login redirect (GET requests only), flashes an error,
  and redirects to the login page.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  @doc """
  Plug: Requires user with admin role.

  If the current user does not have the `:admin` role, flashes
  an error and redirects to the root path.
  """
  def require_admin(conn, _opts) do
    if conn.assigns[:current_user] && conn.assigns[:current_user].role == :admin do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  # LiveView on_mount hooks

  @doc """
  LiveView on_mount hooks for authentication and authorization.

  ## Hooks

    * `:mount_current_user` - Assigns `current_user` to the socket using
      `assign_new/3` so the user is only loaded once per LiveView lifecycle.

    * `:ensure_authenticated` - Mounts the current user, then halts the
      socket with a redirect to the login page if no user is found.

    * `:ensure_admin` - Mounts the current user, then halts the socket
      with a redirect to the root path if the user is not an admin.
  """
  def on_mount(action, params, session, socket)

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket =
      socket
      |> mount_current_user(session)
      |> mount_current_path()

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket =
      socket
      |> mount_current_user(session)
      |> mount_current_path()

    if socket.assigns.current_user && socket.assigns.current_user.role == :admin do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You are not authorized to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  defp mount_current_path(socket) do
    path =
      case socket.private[:connect_info] do
        %{uri: uri} when is_struct(uri, URI) -> uri.path || "/"
        _ -> "/"
      end

    socket
    |> Phoenix.Component.assign(:current_path, path)
    |> Phoenix.LiveView.attach_hook(:update_current_path, :handle_params, fn _params, uri, socket ->
      {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
    end)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/dashboards"
end

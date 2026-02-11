defmodule SwitchTelemetryWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SwitchTelemetryWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SwitchTelemetryWeb.ConnCase

      use SwitchTelemetryWeb, :verified_routes

      # The default endpoint for testing
      @endpoint SwitchTelemetryWeb.Endpoint
    end
  end

  setup tags do
    SwitchTelemetry.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in a user.

  Accepts optional `:role` or `:user_attrs` keys in the context
  to customize the created user.

  ## Examples

      setup :register_and_log_in_user

      setup context do
        %{role: :admin} |> Map.merge(context) |> register_and_log_in_user()
      end

  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = create_test_user(context)
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Creates a test user with optional attributes.

  Accepts a map which may include:
    * `:role` - the user role (`:admin`, `:operator`, or `:viewer`)
    * `:user_attrs` - a map of additional attributes to merge
    * Any other keys are ignored

  ## Examples

      create_test_user()
      create_test_user(%{role: :admin})
      create_test_user(%{user_attrs: %{email: "custom@example.com"}})

  """
  def create_test_user(attrs \\ %{}) do
    base_attrs = %{
      email: "user#{System.unique_integer([:positive])}@example.com",
      password: "valid_password_123"
    }

    # Merge role if provided at the top level
    base_attrs =
      if role = attrs[:role] do
        Map.put(base_attrs, :role, role)
      else
        base_attrs
      end

    # Merge any explicit user_attrs override
    base_attrs =
      if user_attrs = attrs[:user_attrs] do
        Map.merge(base_attrs, user_attrs)
      else
        base_attrs
      end

    {:ok, user} = SwitchTelemetry.Accounts.register_user(base_attrs)
    user
  end

  @doc """
  Logs the given user into the connection by putting the
  session token into the test session.
  """
  def log_in_user(conn, user) do
    token = SwitchTelemetry.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end

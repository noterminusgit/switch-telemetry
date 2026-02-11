defmodule SwitchTelemetry.AccountsTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetry.Accounts.{User, UserToken}

  defp create_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.register_user(
        Map.merge(
          %{
            email: "user#{System.unique_integer([:positive])}@example.com",
            password: "valid_password123"
          },
          attrs
        )
      )

    user
  end

  describe "get_user_by_email/1" do
    test "returns the user if the email exists" do
      %{id: id} = user = create_user()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end

    test "returns nil if the email does not exist" do
      assert Accounts.get_user_by_email("unknown@example.com") == nil
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user if the email and password are valid" do
      %{id: id} = user = create_user()
      assert %User{id: ^id} = Accounts.get_user_by_email_and_password(user.email, "valid_password123")
    end

    test "returns nil if the email does not exist" do
      assert Accounts.get_user_by_email_and_password("unknown@example.com", "valid_password123") == nil
    end

    test "returns nil if the password is wrong" do
      user = create_user()
      assert Accounts.get_user_by_email_and_password(user.email, "wrong_password") == nil
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(Ecto.UUID.generate())
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = create_user()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})
      assert %{email: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email format" do
      {:error, changeset} = Accounts.register_user(%{email: "nope", password: "valid_password123"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates password length" do
      {:error, changeset} = Accounts.register_user(%{email: "test@example.com", password: "short"})
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "validates email uniqueness" do
      user = create_user()
      {:error, changeset} = Accounts.register_user(%{email: user.email, password: "valid_password123"})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = "test#{System.unique_integer([:positive])}@example.com"
      {:ok, user} = Accounts.register_user(%{email: email, password: "valid_password123"})
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      assert is_binary(user.id)
    end

    test "auto-generates a UUID id" do
      {:ok, user} = Accounts.register_user(%{email: "uuid@example.com", password: "valid_password123"})
      assert {:ok, _} = Ecto.UUID.cast(user.id)
    end

    test "defaults role to :viewer" do
      {:ok, user} = Accounts.register_user(%{email: "role@example.com", password: "valid_password123"})
      assert user.role == :viewer
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert :email in changeset.required
      assert :password in changeset.required
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: create_user()}
    end

    test "validates email format", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "valid_password123", %{email: "nope"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "wrong_password", %{email: "new@example.com"})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting", %{user: user} do
      email = "new#{System.unique_integer([:positive])}@example.com"
      {:ok, applied_user} = Accounts.apply_user_email(user, "valid_password123", %{email: email})
      assert applied_user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: create_user()}
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "wrong_password", %{password: "new_valid_password123"})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "validates new password length", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "valid_password123", %{password: "short"})

      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} =
        Accounts.update_user_password(user, "valid_password123", %{password: "new_valid_password123"})

      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(updated_user.email, "new_valid_password123")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _token = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, "valid_password123", %{password: "new_valid_password123"})

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: create_user()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.user_id == user.id
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = create_user()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "returns nil for invalid token" do
      assert Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32)) == nil
    end

    test "returns nil for expired token", %{token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]])

      assert Accounts.get_user_by_session_token(token) == nil
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = create_user()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: create_user()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = create_user()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
    end

    test "returns nil with invalid token" do
      assert Accounts.get_user_by_reset_password_token("invalid") == nil
    end

    test "returns nil with expired token", %{token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]])

      assert Accounts.get_user_by_reset_password_token(token) == nil
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: create_user()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} = Accounts.reset_user_password(user, %{password: "short"})
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new_valid_password123"})
      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new_valid_password123")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _token = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new_valid_password123"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "confirm_user/1" do
    setup do
      user = create_user()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the user", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.id == user.id
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "returns error with invalid token" do
      assert Accounts.confirm_user("invalid") == :error
    end

    test "returns error if token is expired", %{token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]])

      assert Accounts.confirm_user(token) == :error
    end
  end

  describe "list_users/0" do
    test "returns all users ordered by email" do
      user1 = create_user(%{email: "alice@example.com"})
      user2 = create_user(%{email: "bob@example.com"})

      users = Accounts.list_users()
      user_ids = Enum.map(users, & &1.id)

      assert user1.id in user_ids
      assert user2.id in user_ids
    end
  end

  describe "update_user_role/2" do
    setup do
      %{user: create_user()}
    end

    test "updates the role to admin", %{user: user} do
      assert user.role == :viewer
      {:ok, updated} = Accounts.update_user_role(user, %{role: :admin})
      assert updated.role == :admin
    end

    test "updates the role to operator", %{user: user} do
      {:ok, updated} = Accounts.update_user_role(user, %{role: :operator})
      assert updated.role == :operator
    end

    test "rejects invalid role", %{user: user} do
      {:error, changeset} = Accounts.update_user_role(user, %{role: :superuser})
      assert %{role: _} = errors_on(changeset)
    end
  end

  describe "delete_user/1" do
    test "deletes the user" do
      user = create_user()
      {:ok, _} = Accounts.delete_user(user)

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(user.id)
      end
    end

    test "deletes associated tokens" do
      user = create_user()
      _token = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.delete_user(user)
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  defp extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[/TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    [token | _] = String.split(token, "[/TOKEN]")
    token
  end
end

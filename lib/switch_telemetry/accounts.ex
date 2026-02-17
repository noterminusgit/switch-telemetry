defmodule SwitchTelemetry.Accounts do
  @moduledoc """
  The Accounts context. Handles user registration, authentication,
  session management, and account administration.
  """

  import Ecto.Query

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Accounts.{AdminEmail, User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!("valid-id")
      %User{}

      iex> get_user!("invalid-id")
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(String.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{email: "user@example.com", password: "valid_password123"})
      {:ok, %User{}}

      iex> register_user(%{email: "bad"})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    id_key = if is_map_key(attrs, "email"), do: "id", else: :id

    result =
      %User{}
      |> User.registration_changeset(Map.put_new(attrs, id_key, Ecto.UUID.generate()))
      |> Repo.insert()

    case result do
      {:ok, user} ->
        {:ok, maybe_promote_to_admin(user)}

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_registration(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_email(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database. Requires the current password for verification.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: "new@example.com"})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: "new@example.com"})
      {:error, %Ecto.Changeset{}}

  """
  @spec apply_user_email(User.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  @spec update_user_email(User.t(), String.t()) :: {:ok, User.t()} | :error
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_email_token_query(token, context),
         %User{} = _user <- Repo.one(query),
         {:ok, %{user: user}} <- user_email_multi(user, user.email, context) |> Repo.transaction() do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc """
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/\#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(User.t(), String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")
    Repo.insert!(user_token)
    UserNotifier.deliver_confirmation_instructions(user, update_email_url_fun.(encoded_token))
  end

  ## Password

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_password(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: "new_valid_password123"})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: "new_valid_password123"})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_password(User.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  @spec get_user_by_session_token(binary()) :: User.t() | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc """
  Delivers the confirmation instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/\#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, :already_confirmed}
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  @spec confirm_user(String.t()) :: {:ok, User.t()} | :error
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- confirm_user_multi(user) |> Repo.transaction() do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/\#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_reset_password_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("valid-token")
      %User{}

      iex> get_user_by_reset_password_token("invalid-token")
      nil

  """
  @spec get_user_by_reset_password_token(String.t()) :: User.t() | nil
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new_valid_password123"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "short"})
      {:error, %Ecto.Changeset{}}

  """
  @spec reset_user_password(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Admin functions

  @doc """
  Returns the list of all users.
  """
  @spec list_users() :: [User.t()]
  def list_users do
    Repo.all(from u in User, order_by: [asc: u.email])
  end

  @doc """
  Updates a user's role.

  ## Examples

      iex> update_user_role(user, %{role: :admin})
      {:ok, %User{}}

  """
  @spec update_user_role(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_role(%User{} = user, attrs) do
    user
    |> User.role_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user and all associated tokens.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

  """
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  ## Admin Email Allowlist

  @doc """
  Returns the list of all admin emails.
  """
  @spec list_admin_emails() :: [AdminEmail.t()]
  def list_admin_emails do
    Repo.all(from ae in AdminEmail, order_by: [asc: ae.email])
  end

  @doc """
  Gets a single admin email.

  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_admin_email!(term()) :: AdminEmail.t()
  def get_admin_email!(id), do: Repo.get!(AdminEmail, id)

  @doc """
  Creates an admin email allowlist entry.
  """
  @spec create_admin_email(map()) :: {:ok, AdminEmail.t()} | {:error, Ecto.Changeset.t()}
  def create_admin_email(attrs) do
    %AdminEmail{}
    |> AdminEmail.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes an admin email allowlist entry.
  """
  @spec delete_admin_email(AdminEmail.t()) :: {:ok, AdminEmail.t()} | {:error, Ecto.Changeset.t()}
  def delete_admin_email(%AdminEmail{} = admin_email) do
    Repo.delete(admin_email)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking admin email changes.
  """
  @spec change_admin_email(AdminEmail.t(), map()) :: Ecto.Changeset.t()
  def change_admin_email(%AdminEmail{} = admin_email, attrs \\ %{}) do
    AdminEmail.changeset(admin_email, attrs)
  end

  @doc """
  Checks if the given email is on the admin allowlist.
  """
  @spec admin_email?(String.t()) :: boolean()
  def admin_email?(email) when is_binary(email) do
    Repo.exists?(from ae in AdminEmail, where: ae.email == ^email)
  end

  ## Auto-promote

  @doc """
  Promotes a user to admin if their email is on the allowlist.
  Returns the (possibly updated) user.
  """
  @spec maybe_promote_to_admin(User.t()) :: User.t()
  def maybe_promote_to_admin(%User{role: :admin} = user), do: user

  def maybe_promote_to_admin(%User{} = user) do
    if admin_email?(user.email) do
      case update_user_role(user, %{role: :admin}) do
        {:ok, updated_user} -> updated_user
        {:error, _} -> user
      end
    else
      user
    end
  end

  ## Password generation

  @doc """
  Generates a secure random 16-character password.
  """
  @spec generate_password() :: String.t()
  def generate_password do
    :crypto.strong_rand_bytes(12)
    |> Base.url_encode64(padding: false)
  end

  ## Magic link

  @doc """
  Delivers magic link login instructions to the given user.
  """
  @spec deliver_magic_link_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_magic_link_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "magic_link")
    Repo.insert!(user_token)
    UserNotifier.deliver_magic_link(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Verifies a magic link token and returns the user.
  Deletes all magic_link tokens for the user after verification (single-use).
  """
  @spec verify_magic_link_token(String.t()) :: {:ok, User.t()} | :error
  def verify_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "magic_link"),
         %User{} = user <- Repo.one(query) do
      Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["magic_link"]))
      {:ok, user}
    else
      _ -> :error
    end
  end

  @doc """
  Gets or creates a user for magic link login.

  If the user exists, returns `{:ok, user}`.
  If not, creates a new admin account with a generated password,
  auto-confirms it, and emails the generated password.
  """
  @spec get_or_create_user_for_magic_link(String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_user_for_magic_link(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, user}

      nil ->
        password = generate_password()

        attrs = %{
          email: email,
          password: password,
          role: :admin
        }

        case register_user(attrs) do
          {:ok, user} ->
            # Auto-confirm the account
            user
            |> User.confirm_changeset()
            |> Repo.update!()

            UserNotifier.deliver_generated_password(user, password)
            {:ok, Repo.get!(User, user.id)}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end
end

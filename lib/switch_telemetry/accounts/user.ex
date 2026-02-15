defmodule SwitchTelemetry.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :role, Ecto.Enum, values: [:admin, :operator, :viewer], default: :viewer
    field :confirmed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for user registration."
  @spec registration_changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:id, :email, :password, :role])
    |> validate_email()
    |> validate_password(opts)
  end

  @doc "Changeset for changing the email."
  @spec email_changeset(t(), map()) :: Ecto.Changeset.t()
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
  end

  @doc "Changeset for changing the password."
  @spec password_changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc "Changeset for changing the role (admin only)."
  @spec role_changeset(t(), map()) :: Ecto.Changeset.t()
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, [:admin, :operator, :viewer])
  end

  @doc "Confirms the account by setting `confirmed_at`."
  @spec confirm_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(user, confirmed_at: now)
  end

  @doc "Verifies the password. Returns false if user is nil (timing attack prevention)."
  @spec valid_password?(t() | nil, String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc "Validates the current password (for sensitive changes)."
  @spec validate_current_password(Ecto.Changeset.t(), String.t()) :: Ecto.Changeset.t()
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, SwitchTelemetry.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end

defmodule SwitchTelemetry.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # Session tokens are valid for 60 days
  @session_validity_in_days 60
  # Reset password tokens valid for 1 day
  @reset_password_validity_in_days 1

  @type t :: %__MODULE__{}

  @derive {Inspect, except: [:token]}

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, SwitchTelemetry.Accounts.User, type: :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Generates a session token."
  @spec build_session_token(SwitchTelemetry.Accounts.User.t()) :: {binary(), t()}
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  @doc "Checks if the session token is valid and returns its query."
  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Query.t()}
  def verify_session_token_query(token) do
    query =
      from t in __MODULE__,
        where: t.token == ^token and t.context == "session",
        where: t.inserted_at > ago(@session_validity_in_days, "day"),
        join: u in assoc(t, :user),
        select: u

    {:ok, query}
  end

  @doc "Builds a hashed token for password reset."
  @spec build_email_token(SwitchTelemetry.Accounts.User.t(), String.t()) :: {String.t(), t()}
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc "Checks if the email token is valid and returns its query."
  @spec verify_email_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in __MODULE__,
            where: t.token == ^hashed_token and t.context == ^context,
            where: t.inserted_at > ago(@reset_password_validity_in_days, "day"),
            join: u in assoc(t, :user),
            select: u

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Returns the token struct for the given context."
  @spec by_user_and_contexts_query(SwitchTelemetry.Accounts.User.t(), :all | [String.t()]) ::
          Ecto.Query.t()
  def by_user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc "Returns the token struct matching the given token value and context."
  @spec token_and_context_query(binary(), String.t()) :: Ecto.Query.t()
  def token_and_context_query(token, context) do
    from t in __MODULE__, where: t.token == ^token and t.context == ^context
  end
end

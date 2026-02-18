defmodule SwitchTelemetry.Settings do
  @moduledoc """
  The Settings context. Manages application-wide configuration
  stored in PostgreSQL, such as SMTP settings.
  """

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Settings.{SecuritySetting, SmtpSetting}

  @doc """
  Returns the SMTP settings (single-row table).
  Creates a default row if none exists.
  """
  @spec get_smtp_settings() :: SmtpSetting.t()
  def get_smtp_settings do
    case Repo.get(SmtpSetting, 1) do
      nil ->
        %SmtpSetting{id: 1}
        |> Repo.insert!()

      setting ->
        setting
    end
  end

  @doc """
  Updates the SMTP settings. Creates the row if it doesn't exist.
  """
  @spec update_smtp_settings(map()) :: {:ok, SmtpSetting.t()} | {:error, Ecto.Changeset.t()}
  def update_smtp_settings(attrs) do
    get_smtp_settings()
    |> SmtpSetting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking SMTP setting changes.
  """
  @spec change_smtp_settings(SmtpSetting.t(), map()) :: Ecto.Changeset.t()
  def change_smtp_settings(%SmtpSetting{} = smtp_setting, attrs \\ %{}) do
    SmtpSetting.changeset(smtp_setting, attrs)
  end

  # --- Security Settings ---

  @doc """
  Returns the security settings (single-row table).
  Creates a default row if none exists.
  """
  @spec get_security_settings() :: SecuritySetting.t()
  def get_security_settings do
    case Repo.get(SecuritySetting, 1) do
      nil ->
        %SecuritySetting{id: 1}
        |> Repo.insert!()

      setting ->
        setting
    end
  end

  @doc """
  Updates the security settings. Creates the row if it doesn't exist.
  """
  @spec update_security_settings(map()) ::
          {:ok, SecuritySetting.t()} | {:error, Ecto.Changeset.t()}
  def update_security_settings(attrs) do
    get_security_settings()
    |> SecuritySetting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking security setting changes.
  """
  @spec change_security_settings(SecuritySetting.t(), map()) :: Ecto.Changeset.t()
  def change_security_settings(%SecuritySetting{} = security_setting, attrs \\ %{}) do
    SecuritySetting.changeset(security_setting, attrs)
  end
end

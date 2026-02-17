defmodule SwitchTelemetry.Mailer do
  use Swoosh.Mailer, otp_app: :switch_telemetry

  alias SwitchTelemetry.Settings

  @doc """
  Returns dynamic mailer config from DB if SMTP is enabled,
  otherwise returns empty list to use application config defaults.
  """
  def dynamic_config do
    try do
      smtp = Settings.get_smtp_settings()

      if smtp.enabled && smtp.relay && smtp.relay != "" do
        config = [
          adapter: Swoosh.Adapters.SMTP,
          relay: smtp.relay,
          port: smtp.port || 587,
          tls: if(smtp.tls, do: :always, else: :never)
        ]

        config =
          if smtp.username && smtp.username != "" do
            config ++ [username: smtp.username, password: smtp.password]
          else
            config
          end

        config
      else
        []
      end
    rescue
      # DB not available (migrations not run, etc) — fall back to app config
      _ -> []
    end
  end
end

defmodule SwitchTelemetry.Repo.Migrations.EncryptCredentialFields do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE credentials ALTER COLUMN password TYPE bytea USING password::bytea"
    execute "ALTER TABLE credentials ALTER COLUMN ssh_key TYPE bytea USING ssh_key::bytea"
    execute "ALTER TABLE credentials ALTER COLUMN tls_cert TYPE bytea USING tls_cert::bytea"
    execute "ALTER TABLE credentials ALTER COLUMN tls_key TYPE bytea USING tls_key::bytea"
  end

  def down do
    execute "ALTER TABLE credentials ALTER COLUMN password TYPE text USING encode(password, 'escape')"
    execute "ALTER TABLE credentials ALTER COLUMN ssh_key TYPE text USING encode(ssh_key, 'escape')"
    execute "ALTER TABLE credentials ALTER COLUMN tls_cert TYPE text USING encode(tls_cert, 'escape')"
    execute "ALTER TABLE credentials ALTER COLUMN tls_key TYPE text USING encode(tls_key, 'escape')"
  end
end

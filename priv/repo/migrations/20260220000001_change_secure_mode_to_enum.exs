defmodule SwitchTelemetry.Repo.Migrations.ChangeSecureModeToEnum do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add :secure_mode_new, :string, default: "insecure", null: false
    end

    execute """
    UPDATE devices SET secure_mode_new = CASE
      WHEN secure_mode = true THEN 'tls_verified'
      ELSE 'insecure'
    END
    """

    alter table(:devices) do
      remove :secure_mode
    end

    rename table(:devices), :secure_mode_new, to: :secure_mode
  end

  def down do
    alter table(:devices) do
      add :secure_mode_old, :boolean, default: false, null: false
    end

    execute """
    UPDATE devices SET secure_mode_old = CASE
      WHEN secure_mode = 'tls_verified' THEN true
      WHEN secure_mode = 'mtls' THEN true
      ELSE false
    END
    """

    alter table(:devices) do
      remove :secure_mode
    end

    rename table(:devices), :secure_mode_old, to: :secure_mode
  end
end

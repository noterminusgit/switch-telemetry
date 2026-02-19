defmodule SwitchTelemetry.Settings.SecuritySettingTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Settings
  alias SwitchTelemetry.Settings.SecuritySetting
  alias SwitchTelemetry.Repo

  describe "get_security_settings/0" do
    test "creates default record when none exists" do
      refute Repo.get(SecuritySetting, 1)

      settings = Settings.get_security_settings()

      assert %SecuritySetting{id: 1} = settings
      assert settings.require_secure_gnmi == false
      assert settings.require_credentials == false
      assert Repo.get(SecuritySetting, 1) != nil
    end

    test "returns existing record when one exists" do
      {:ok, created} =
        Settings.update_security_settings(%{
          require_secure_gnmi: true,
          require_credentials: true
        })

      fetched = Settings.get_security_settings()
      assert fetched.id == created.id
      assert fetched.require_secure_gnmi == true
      assert fetched.require_credentials == true
    end
  end

  describe "update_security_settings/1" do
    test "updates settings with valid data" do
      {:ok, updated} =
        Settings.update_security_settings(%{
          require_secure_gnmi: true,
          require_credentials: false
        })

      assert updated.require_secure_gnmi == true
      assert updated.require_credentials == false
    end

    test "updates only specified fields" do
      Settings.get_security_settings()

      {:ok, updated} = Settings.update_security_settings(%{require_secure_gnmi: true})

      assert updated.require_secure_gnmi == true
      assert updated.require_credentials == false
    end
  end

  describe "change_security_settings/2" do
    test "returns changeset without attributes" do
      settings = Settings.get_security_settings()
      changeset = Settings.change_security_settings(settings)

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes == %{}
    end

    test "returns changeset with attributes" do
      settings = Settings.get_security_settings()

      changeset =
        Settings.change_security_settings(settings, %{
          require_secure_gnmi: true
        })

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :require_secure_gnmi) == true
    end
  end

  describe "SecuritySetting changeset" do
    test "accepts boolean values" do
      changeset =
        %SecuritySetting{}
        |> SecuritySetting.changeset(%{
          require_secure_gnmi: true,
          require_credentials: true
        })

      assert Ecto.Changeset.get_change(changeset, :require_secure_gnmi) == true
      assert Ecto.Changeset.get_change(changeset, :require_credentials) == true
    end

    test "defaults are false" do
      settings = %SecuritySetting{}
      assert settings.require_secure_gnmi == false
      assert settings.require_credentials == false
    end
  end
end

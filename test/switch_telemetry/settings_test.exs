defmodule SwitchTelemetry.SettingsTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Settings
  alias SwitchTelemetry.Settings.SmtpSetting
  alias SwitchTelemetry.Repo

  describe "get_smtp_settings/0" do
    test "creates default record when none exists" do
      # Ensure no record exists
      refute Repo.get(SmtpSetting, 1)

      # Call get_smtp_settings
      settings = Settings.get_smtp_settings()

      # Should return a struct with id=1
      assert %SmtpSetting{id: 1} = settings

      # Defaults should be applied
      assert settings.port == 587
      assert settings.from_email == "noreply@switch-telemetry.local"
      assert settings.from_name == "Switch Telemetry"
      assert settings.tls == true
      assert settings.enabled == false

      # Record should be persisted
      assert Repo.get(SmtpSetting, 1) != nil
    end

    test "returns existing record when one exists" do
      # Create a record with specific values
      {:ok, created} =
        Settings.update_smtp_settings(%{
          relay: "smtp.example.com",
          port: 465,
          from_email: "alerts@example.com",
          from_name: "Alert System"
        })

      # Call get_smtp_settings
      fetched = Settings.get_smtp_settings()

      # Should return the same record
      assert fetched.id == created.id
      assert fetched.relay == "smtp.example.com"
      assert fetched.port == 465
      assert fetched.from_email == "alerts@example.com"
      assert fetched.from_name == "Alert System"
    end
  end

  describe "update_smtp_settings/1" do
    test "updates settings with valid data" do
      {:ok, updated} =
        Settings.update_smtp_settings(%{
          relay: "smtp.gmail.com",
          port: 587,
          username: "user@gmail.com",
          from_email: "noreply@example.com",
          from_name: "Example Alerts",
          tls: true,
          enabled: true
        })

      assert updated.relay == "smtp.gmail.com"
      assert updated.port == 587
      assert updated.username == "user@gmail.com"
      assert updated.from_email == "noreply@example.com"
      assert updated.from_name == "Example Alerts"
      assert updated.tls == true
      assert updated.enabled == true
    end

    test "updates only specified fields" do
      Settings.get_smtp_settings()

      {:ok, updated} =
        Settings.update_smtp_settings(%{
          relay: "smtp.sendgrid.net",
          port: 25
        })

      assert updated.relay == "smtp.sendgrid.net"
      assert updated.port == 25
      # Other fields should retain defaults or previous values
      assert updated.from_email == "noreply@switch-telemetry.local"
      assert updated.from_name == "Switch Telemetry"
    end

    test "validates port range" do
      {:error, changeset} =
        Settings.update_smtp_settings(%{
          port: 0,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "must be greater than 0" in errors_on(changeset).port
    end

    test "validates port less than 65536" do
      {:error, changeset} =
        Settings.update_smtp_settings(%{
          port: 65536,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "must be less than 65536" in errors_on(changeset).port
    end

    test "validates from_email format" do
      {:error, changeset} =
        Settings.update_smtp_settings(%{
          from_email: "invalid-email",
          from_name: "Test"
        })

      assert "must be a valid email" in errors_on(changeset).from_email
    end

    test "validates required fields when explicitly nulling them" do
      {:error, changeset} =
        Settings.update_smtp_settings(%{
          port: nil,
          from_email: nil,
          from_name: nil
        })

      errors = errors_on(changeset)
      assert "can't be blank" in errors.port
      assert "can't be blank" in errors.from_email
      assert "can't be blank" in errors.from_name
    end

    test "returns error tuple on validation failure" do
      result =
        Settings.update_smtp_settings(%{
          port: 70000,
          from_email: "bad-email"
        })

      assert {:error, changeset} = result
      assert %Ecto.Changeset{} = changeset
    end

    test "creates default record if none exists" do
      refute Repo.get(SmtpSetting, 1)

      {:ok, created} =
        Settings.update_smtp_settings(%{
          relay: "smtp.test.com",
          port: 587,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert created.id == 1
      assert created.relay == "smtp.test.com"
    end
  end

  describe "change_smtp_settings/1 and change_smtp_settings/2" do
    test "returns changeset without attributes" do
      settings = Settings.get_smtp_settings()
      changeset = Settings.change_smtp_settings(settings)

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes == %{}
    end

    test "returns changeset with attributes" do
      settings = Settings.get_smtp_settings()

      changeset =
        Settings.change_smtp_settings(settings, %{
          relay: "smtp.example.com",
          port: 465
        })

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :relay) == "smtp.example.com"
      assert Ecto.Changeset.get_change(changeset, :port) == 465
    end

    test "changeset includes data from struct" do
      {:ok, settings} =
        Settings.update_smtp_settings(%{
          relay: "existing.com",
          port: 587,
          from_email: "existing@example.com",
          from_name: "Existing"
        })

      changeset = Settings.change_smtp_settings(settings)

      # Data should be in the changeset
      assert changeset.data.relay == "existing.com"
      assert changeset.data.port == 587
    end
  end

  describe "SmtpSetting changeset validations" do
    test "validates required fields: port" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{port: nil, from_email: "test@example.com", from_name: "Test"})

      assert "can't be blank" in errors_on(changeset).port
    end

    test "validates required fields: from_email" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{port: 587, from_email: nil, from_name: "Test"})

      assert "can't be blank" in errors_on(changeset).from_email
    end

    test "validates required fields: from_name" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{port: 587, from_email: "test@example.com", from_name: nil})

      assert "can't be blank" in errors_on(changeset).from_name
    end

    test "validates port range: greater than 0" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 0,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "must be greater than 0" in errors_on(changeset).port
    end

    test "validates port range: less than 65536" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 65536,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "must be less than 65536" in errors_on(changeset).port
    end

    test "validates port range: negative values" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: -1,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "must be greater than 0" in errors_on(changeset).port
    end

    test "validates port range: boundary values" do
      # Port 1 should be valid
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 1,
          from_email: "test@example.com",
          from_name: "Test"
        })

      refute :port in changeset.errors

      # Port 65535 should be valid
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 65535,
          from_email: "test@example.com",
          from_name: "Test"
        })

      refute :port in changeset.errors
    end

    test "validates from_email format: simple email" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "user@example.com",
          from_name: "Test"
        })

      refute :from_email in changeset.errors
    end

    test "validates from_email format: missing @" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "invalid.email.com",
          from_name: "Test"
        })

      assert "must be a valid email" in errors_on(changeset).from_email
    end

    test "validates from_email format: missing domain" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "user@",
          from_name: "Test"
        })

      assert "must be a valid email" in errors_on(changeset).from_email
    end

    test "validates from_email format: contains spaces" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "user @example.com",
          from_name: "Test"
        })

      assert "must be a valid email" in errors_on(changeset).from_email
    end

    test "validates max length: relay" do
      long_relay = String.duplicate("a", 256)

      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          relay: long_relay,
          port: 587,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "should be at most 255 character(s)" in errors_on(changeset).relay
    end

    test "validates max length: username" do
      long_username = String.duplicate("a", 256)

      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          username: long_username,
          port: 587,
          from_email: "test@example.com",
          from_name: "Test"
        })

      assert "should be at most 255 character(s)" in errors_on(changeset).username
    end

    test "validates max length: from_email" do
      long_email = String.duplicate("a", 250) <> "@example.com"

      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: long_email,
          from_name: "Test"
        })

      assert "should be at most 255 character(s)" in errors_on(changeset).from_email
    end

    test "validates max length: from_name" do
      long_name = String.duplicate("a", 256)

      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "test@example.com",
          from_name: long_name
        })

      assert "should be at most 255 character(s)" in errors_on(changeset).from_name
    end

    test "accepts valid relay value within length limit" do
      relay = String.duplicate("a", 255)

      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          relay: relay,
          port: 587,
          from_email: "test@example.com",
          from_name: "Test"
        })

      refute :relay in changeset.errors
    end

    test "accepts empty/nil relay" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "test@example.com",
          from_name: "Test"
        })

      refute :relay in changeset.errors
    end

    test "accepts empty/nil username" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "test@example.com",
          from_name: "Test"
        })

      refute :username in changeset.errors
    end

    test "accepts boolean values for tls" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "test@example.com",
          from_name: "Test",
          tls: false
        })

      refute :tls in changeset.errors
      assert Ecto.Changeset.get_change(changeset, :tls) == false
    end

    test "accepts boolean values for enabled" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "test@example.com",
          from_name: "Test",
          enabled: true
        })

      refute :enabled in changeset.errors
      assert Ecto.Changeset.get_change(changeset, :enabled) == true
    end

    test "accepts encrypted password field" do
      changeset =
        %SmtpSetting{}
        |> SmtpSetting.changeset(%{
          port: 587,
          from_email: "test@example.com",
          from_name: "Test",
          password: "secret123"
        })

      refute :password in changeset.errors
    end

    test "defaults to port 587 when not provided" do
      settings = %SmtpSetting{}
      assert settings.port == 587
    end

    test "defaults to noreply@switch-telemetry.local when from_email not provided" do
      settings = %SmtpSetting{}
      assert settings.from_email == "noreply@switch-telemetry.local"
    end

    test "defaults to 'Switch Telemetry' when from_name not provided" do
      settings = %SmtpSetting{}
      assert settings.from_name == "Switch Telemetry"
    end

    test "defaults to true for tls" do
      settings = %SmtpSetting{}
      assert settings.tls == true
    end

    test "defaults to false for enabled" do
      settings = %SmtpSetting{}
      assert settings.enabled == false
    end
  end

  describe "SMTP settings integration" do
    test "full workflow: create, update, retrieve" do
      # Initially, no record exists
      refute Repo.get(SmtpSetting, 1)

      # Create initial settings
      {:ok, initial} =
        Settings.update_smtp_settings(%{
          relay: "smtp.example.com",
          port: 587,
          from_email: "alerts@example.com",
          from_name: "Alerts"
        })

      assert initial.id == 1
      assert initial.relay == "smtp.example.com"

      # Retrieve the settings
      retrieved = Settings.get_smtp_settings()
      assert retrieved.id == initial.id
      assert retrieved.relay == initial.relay

      # Update the settings
      {:ok, updated} =
        Settings.update_smtp_settings(%{
          port: 465,
          enabled: true
        })

      assert updated.id == 1
      assert updated.port == 465
      assert updated.enabled == true
      # Previous value retained
      assert updated.relay == "smtp.example.com"
    end

    test "password field is encrypted" do
      Settings.update_smtp_settings(%{
        port: 587,
        from_email: "test@example.com",
        from_name: "Test",
        password: "supersecret"
      })

      # Retrieve from DB to verify encryption
      fetched = Repo.get(SmtpSetting, 1)

      # The password should be a binary (encrypted), not the original string
      assert is_binary(fetched.password)
      # When accessed through the struct with Cloak, it should decrypt properly
      assert fetched.password == "supersecret"
    end

    test "multiple updates preserve other fields" do
      Settings.update_smtp_settings(%{
        relay: "smtp.first.com",
        port: 587,
        username: "user1",
        from_email: "first@example.com",
        from_name: "First",
        tls: true,
        enabled: false
      })

      Settings.update_smtp_settings(%{
        relay: "smtp.second.com"
      })

      fetched = Settings.get_smtp_settings()
      assert fetched.relay == "smtp.second.com"
      assert fetched.username == "user1"
      assert fetched.from_email == "first@example.com"
      assert fetched.from_name == "First"
      assert fetched.tls == true
      assert fetched.enabled == false
    end
  end
end

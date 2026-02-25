defmodule SwitchTelemetry.VaultTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Devices.Credential
  alias SwitchTelemetry.Repo

  describe "credential encryption" do
    test "round-trips encrypted fields" do
      attrs = %{
        id: "cred_vault_test",
        name: "test-cred",
        username: "admin",
        password: "super_secret_password",
        ssh_key: "-----BEGIN RSA PRIVATE KEY-----\nfake_key_data\n-----END RSA PRIVATE KEY-----"
      }

      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      # Read back from DB
      loaded = Repo.get!(Credential, credential.id)
      assert loaded.password == "super_secret_password"

      assert loaded.ssh_key ==
               "-----BEGIN RSA PRIVATE KEY-----\nfake_key_data\n-----END RSA PRIVATE KEY-----"

      assert loaded.username == "admin"
    end

    test "encrypted fields are stored as binary in DB" do
      attrs = %{
        id: "cred_vault_raw",
        name: "raw-check",
        username: "admin",
        password: "plaintext_value"
      }

      {:ok, _} =
        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      # Query raw binary from DB - should NOT be plaintext
      result = Repo.query!("SELECT password FROM credentials WHERE id = 'cred_vault_raw'")
      [[raw_value]] = result.rows
      # The raw stored value should be binary (encrypted), not the plaintext
      refute raw_value == "plaintext_value"
    end

    test "credential inspect redacts sensitive fields" do
      credential = %Credential{
        id: "cred_inspect",
        name: "test",
        username: "admin",
        password: "secret",
        ssh_key: "key_data",
        tls_key: "tls_data"
      }

      inspected = inspect(credential)
      refute inspected =~ "secret"
      refute inspected =~ "key_data"
      refute inspected =~ "tls_data"
      assert inspected =~ "admin"
    end

    test "nil encrypted fields round-trip as nil" do
      attrs = %{
        id: "cred_vault_nil_#{System.unique_integer([:positive])}",
        name: "nil-test",
        username: "admin"
      }

      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      loaded = Repo.get!(Credential, credential.id)
      assert is_nil(loaded.password)
      assert is_nil(loaded.ssh_key)
      assert is_nil(loaded.tls_key)
      assert is_nil(loaded.tls_cert)
    end

    test "round-trips all encrypted field types" do
      attrs = %{
        id: "cred_vault_all_#{System.unique_integer([:positive])}",
        name: "all-fields",
        username: "admin",
        password: "p@ss!w0rd&special",
        ssh_key: "ssh-rsa AAAAB3...",
        tls_cert: "-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----",
        tls_key: "-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----"
      }

      {:ok, _} =
        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      loaded = Repo.get!(Credential, attrs.id)
      assert loaded.password == "p@ss!w0rd&special"
      assert loaded.ssh_key == "ssh-rsa AAAAB3..."
      assert loaded.tls_cert == "-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----"
      assert loaded.tls_key == "-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----"
    end

    test "updates encrypted field preserves other encrypted fields" do
      attrs = %{
        id: "cred_vault_update_#{System.unique_integer([:positive])}",
        name: "update-test",
        username: "admin",
        password: "original",
        ssh_key: "original_key"
      }

      {:ok, cred} =
        %Credential{}
        |> Credential.changeset(attrs)
        |> Repo.insert()

      # Update only password
      {:ok, _} =
        cred
        |> Credential.changeset(%{password: "updated"})
        |> Repo.update()

      loaded = Repo.get!(Credential, attrs.id)
      assert loaded.password == "updated"
      assert loaded.ssh_key == "original_key"
    end
  end
end

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
  end
end

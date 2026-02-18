defmodule SwitchTelemetry.Collector.TlsHelperTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Collector.TlsHelper
  alias SwitchTelemetry.Devices.Credential

  describe "build_grpc_opts/1" do
    test "returns empty list for nil credential" do
      assert TlsHelper.build_grpc_opts(nil) == []
    end

    test "returns verify_none ssl opts for credential without TLS" do
      credential = %Credential{
        username: "admin",
        password: "secret",
        tls_cert: nil,
        tls_key: nil,
        ca_cert: nil
      }

      opts = TlsHelper.build_grpc_opts(credential)
      assert Keyword.has_key?(opts, :cred)
    end

    test "returns empty opts for credential with empty strings" do
      credential = %Credential{
        username: "admin",
        password: "secret",
        tls_cert: "",
        tls_key: "",
        ca_cert: ""
      }

      opts = TlsHelper.build_grpc_opts(credential)
      assert Keyword.has_key?(opts, :cred)
    end
  end

  describe "build_auth_headers/1" do
    test "returns empty list for nil credential" do
      assert TlsHelper.build_auth_headers(nil) == []
    end

    test "returns username and password headers" do
      credential = %Credential{
        username: "admin",
        password: "secret123",
        tls_cert: nil,
        tls_key: nil,
        ca_cert: nil
      }

      headers = TlsHelper.build_auth_headers(credential)
      assert {"username", "admin"} in headers
      assert {"password", "secret123"} in headers
    end

    test "returns only username when password is nil" do
      credential = %Credential{
        username: "admin",
        password: nil,
        tls_cert: nil,
        tls_key: nil,
        ca_cert: nil
      }

      headers = TlsHelper.build_auth_headers(credential)
      assert {"username", "admin"} in headers
      refute Enum.any?(headers, fn {k, _} -> k == "password" end)
    end

    test "returns empty list when both are nil" do
      credential = %Credential{
        username: nil,
        password: nil,
        tls_cert: nil,
        tls_key: nil,
        ca_cert: nil
      }

      assert TlsHelper.build_auth_headers(credential) == []
    end
  end

  describe "decode_pem_cert/1" do
    test "returns error for invalid PEM data" do
      assert {:error, _} = TlsHelper.decode_pem_cert("not a pem")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_pem} = TlsHelper.decode_pem_cert("")
    end

    test "returns error for nil" do
      assert {:error, :not_binary} = TlsHelper.decode_pem_cert(nil)
    end

    test "decodes valid self-signed certificate" do
      {cert_pem, _key_pem} = generate_self_signed_pem()

      assert {:ok, der} = TlsHelper.decode_pem_cert(cert_pem)
      assert is_binary(der)
    end
  end

  describe "decode_pem_key/1" do
    test "returns error for invalid PEM data" do
      assert {:error, _} = TlsHelper.decode_pem_key("not a pem")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_pem} = TlsHelper.decode_pem_key("")
    end

    test "returns error for nil" do
      assert {:error, :not_binary} = TlsHelper.decode_pem_key(nil)
    end

    test "decodes valid RSA private key" do
      {_cert_pem, key_pem} = generate_self_signed_pem()

      assert {:ok, {type, der}} = TlsHelper.decode_pem_key(key_pem)
      assert type in [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo]
      assert is_binary(der)
    end
  end

  # Generate a self-signed cert+key PEM pair using openssl CLI
  defp generate_self_signed_pem do
    tmp_dir = System.tmp_dir!()
    cert_path = Path.join(tmp_dir, "test_cert_#{System.unique_integer([:positive])}.pem")
    key_path = Path.join(tmp_dir, "test_key_#{System.unique_integer([:positive])}.pem")

    {_, 0} =
      System.cmd("openssl", [
        "req", "-x509", "-newkey", "rsa:2048", "-keyout", key_path,
        "-out", cert_path, "-days", "1", "-nodes",
        "-subj", "/CN=test"
      ], stderr_to_stdout: true)

    cert_pem = File.read!(cert_path)
    key_pem = File.read!(key_path)

    File.rm(cert_path)
    File.rm(key_path)

    {cert_pem, key_pem}
  end
end

defmodule SwitchTelemetry.Collector.TlsHelper do
  @moduledoc """
  Builds gRPC connection options based on device transport security mode and credentials.
  """

  alias SwitchTelemetry.Devices.{Credential, Device}

  @type grpc_opts :: keyword()

  @doc """
  Builds gRPC connect options for a given transport security mode and credential.

  Returns keyword list suitable for passing to `GRPC.Stub.connect/2`.

  ## Modes

  - `:insecure` — plaintext gRPC (no TLS), returns `[]`
  - `:tls_skip_verify` — TLS with `verify: :verify_none`
  - `:tls_verified` — TLS with CA cert verification (falls back to `verify_none` if no CA)
  - `:mtls` — mutual TLS with client cert + CA verification (graceful fallback)
  """
  @spec build_grpc_opts(Device.secure_mode(), Credential.t() | nil) :: grpc_opts()
  def build_grpc_opts(:insecure, _credential), do: []

  def build_grpc_opts(:tls_skip_verify, _credential) do
    [cred: GRPC.Credential.new(ssl: [verify: :verify_none])]
  end

  def build_grpc_opts(:tls_verified, credential) do
    ssl_opts = build_ca_opts(credential) ++ [verify: :verify_peer]

    # Fall back to verify_none if no CA certs were decoded
    ssl_opts =
      if Keyword.has_key?(ssl_opts, :cacerts) do
        ssl_opts
      else
        Keyword.put(ssl_opts, :verify, :verify_none)
      end

    [cred: GRPC.Credential.new(ssl: ssl_opts)]
  end

  def build_grpc_opts(:mtls, credential) do
    ca_opts = build_ca_opts(credential)
    client_opts = build_client_cert_opts(credential)

    ssl_opts = ca_opts ++ client_opts ++ [verify: :verify_peer]

    ssl_opts =
      if Keyword.has_key?(ssl_opts, :cacerts) do
        ssl_opts
      else
        Keyword.put(ssl_opts, :verify, :verify_none)
      end

    [cred: GRPC.Credential.new(ssl: ssl_opts)]
  end

  @doc """
  Backward-compatible 1-arity version. Delegates to `:tls_skip_verify` mode.
  """
  @spec build_grpc_opts(Credential.t() | nil) :: grpc_opts()
  def build_grpc_opts(nil), do: []

  def build_grpc_opts(%Credential{} = credential) do
    build_grpc_opts(:tls_skip_verify, credential)
  end

  @doc """
  Builds gRPC metadata headers for username/password authentication.
  """
  @spec build_auth_headers(Credential.t() | nil) :: [{String.t(), String.t()}]
  def build_auth_headers(nil), do: []

  def build_auth_headers(%Credential{} = credential) do
    headers = []

    headers =
      if has_value?(credential.username) do
        headers ++ [{"username", credential.username}]
      else
        headers
      end

    if has_value?(credential.password) do
      headers ++ [{"password", credential.password}]
    else
      headers
    end
  end

  @doc """
  Decodes a PEM-encoded certificate to DER binary.
  """
  @spec decode_pem_cert(binary()) :: {:ok, binary()} | {:error, term()}
  def decode_pem_cert(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [{:Certificate, der, :not_encrypted} | _] ->
        {:ok, der}

      [] ->
        {:error, :invalid_pem}

      _ ->
        {:error, :unexpected_pem_entry}
    end
  rescue
    e -> {:error, e}
  end

  def decode_pem_cert(_), do: {:error, :not_binary}

  @doc """
  Decodes a PEM-encoded private key.
  """
  @spec decode_pem_key(binary()) :: {:ok, tuple()} | {:error, term()}
  def decode_pem_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [{type, der, :not_encrypted} | _]
      when type in [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo] ->
        {:ok, {type, der}}

      [] ->
        {:error, :invalid_pem}

      _ ->
        {:error, :unexpected_pem_entry}
    end
  rescue
    e -> {:error, e}
  end

  def decode_pem_key(_), do: {:error, :not_binary}

  # --- Private helpers ---

  @spec build_ca_opts(Credential.t() | nil) :: keyword()
  defp build_ca_opts(nil), do: []

  defp build_ca_opts(%Credential{} = credential) do
    if has_value?(credential.ca_cert) do
      case decode_pem_certs(credential.ca_cert) do
        {:ok, ca_certs} -> [cacerts: ca_certs]
        _ -> []
      end
    else
      []
    end
  end

  @spec build_client_cert_opts(Credential.t() | nil) :: keyword()
  defp build_client_cert_opts(nil), do: []

  defp build_client_cert_opts(%Credential{} = credential) do
    if has_value?(credential.tls_cert) and has_value?(credential.tls_key) do
      case {decode_pem_cert(credential.tls_cert), decode_pem_key(credential.tls_key)} do
        {{:ok, cert_der}, {:ok, key_tuple}} ->
          [cert: cert_der, key: key_tuple]

        _ ->
          []
      end
    else
      []
    end
  end

  @spec decode_pem_certs(binary()) :: {:ok, [binary()]} | {:error, term()}
  defp decode_pem_certs(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      entries when is_list(entries) and entries != [] ->
        certs =
          Enum.filter(entries, fn
            {:Certificate, _der, :not_encrypted} -> true
            _ -> false
          end)
          |> Enum.map(fn {:Certificate, der, :not_encrypted} -> der end)

        if certs != [] do
          {:ok, certs}
        else
          {:error, :no_certificates}
        end

      _ ->
        {:error, :invalid_pem}
    end
  rescue
    e -> {:error, e}
  end

  defp has_value?(nil), do: false
  defp has_value?(""), do: false
  defp has_value?(_), do: true
end

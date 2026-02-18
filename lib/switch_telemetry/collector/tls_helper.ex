defmodule SwitchTelemetry.Collector.TlsHelper do
  @moduledoc """
  Builds gRPC connection options from device credentials for TLS/SSL support.
  """

  alias SwitchTelemetry.Devices.Credential

  @type grpc_opts :: keyword()

  @doc """
  Builds gRPC connect options from a credential.

  Returns keyword list suitable for passing to `GRPC.Stub.connect/2`.

  - If credential is nil: returns `[]`
  - If credential has `tls_cert` + `tls_key`: mTLS with client cert auth
  - If credential has `ca_cert`: server verification enabled
  - If neither: `verify: :verify_none` (insecure, for labs)
  """
  @spec build_grpc_opts(Credential.t() | nil) :: grpc_opts()
  def build_grpc_opts(nil), do: []

  def build_grpc_opts(%Credential{} = credential) do
    ssl_opts = build_ssl_opts(credential)

    if ssl_opts == [] do
      []
    else
      [cred: GRPC.Credential.new(ssl: ssl_opts)]
    end
  end

  @spec build_ssl_opts(Credential.t()) :: keyword()
  defp build_ssl_opts(credential) do
    opts = []

    opts =
      if has_value?(credential.tls_cert) and has_value?(credential.tls_key) do
        case {decode_pem_cert(credential.tls_cert), decode_pem_key(credential.tls_key)} do
          {{:ok, cert_der}, {:ok, key_tuple}} ->
            opts ++ [cert: cert_der, key: key_tuple]

          _ ->
            opts
        end
      else
        opts
      end

    opts =
      if has_value?(credential.ca_cert) do
        case decode_pem_certs(credential.ca_cert) do
          {:ok, ca_certs} ->
            opts ++ [cacerts: ca_certs, verify: :verify_peer]

          _ ->
            opts
        end
      else
        if opts != [] do
          opts ++ [verify: :verify_none]
        else
          opts ++ [verify: :verify_none]
        end
      end

    opts
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
      [{type, der, :not_encrypted} | _] when type in [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo] ->
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

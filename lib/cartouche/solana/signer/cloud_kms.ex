if Code.ensure_loaded?(Goth) do
  defmodule Cartouche.Solana.Signer.CloudKMS do
    @moduledoc """
    Ed25519 signing backend using Google Cloud KMS.

    GCP KMS supports Ed25519 signing (algorithm `EC_SIGN_ED25519`) since
    April 2024. This is the Solana equivalent of `Cartouche.Signer.CloudKMS`
    for Ethereum.

    Key differences from the Ethereum KMS signer:
    - Uses `data` field (raw bytes) instead of `digest.sha256` (pre-hashed)
    - PEM contains Ed25519 SubjectPublicKeyInfo (RFC 8410), not an EC point
    - Signature is raw 64 bytes, not DER-encoded

    Implements `Cartouche.Signer.Backend` — its `config` is the
    `{credentials, project, location, keychain, key, version}` key-coordinate
    tuple. Ed25519 signs raw message bytes, so
    `c:Cartouche.Signer.Backend.sign_payload/2` is the raw-message signer.
    """
    @behaviour Cartouche.Signer.Backend

    @kms_base_url "https://cloudkms.googleapis.com/v1"

    # Ed25519 SubjectPublicKeyInfo DER prefix (12 bytes):
    # SEQUENCE { SEQUENCE { OID 1.3.101.112 (id-Ed25519) } BIT STRING ... }
    @ed25519_der_prefix <<0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00>>

    @typedoc "Cloud KMS key coordinates: `{credentials, project, location, keychain, key, version}`."
    @type config :: {term(), String.t(), String.t(), String.t(), String.t(), String.t()}

    @impl true
    @spec algorithm(config()) :: :ed25519
    def algorithm(_config), do: :ed25519

    @doc """
    Get the Ed25519 public key (32 bytes) from a KMS key version.

    For Solana the public key *is* the address, so `get_address/6` is an alias.
    """
    @impl true
    @spec public_key(config()) :: {:ok, <<_::256>>} | {:error, term()}
    def public_key({cred, project, location, keychain, key, version}) do
      name = key_version_name(project, location, keychain, key, version)

      with {:ok, %{"algorithm" => algorithm, "pem" => pem}} <- get_public_key(credential_token(cred), name) do
        case algorithm do
          "EC_SIGN_ED25519" ->
            extract_ed25519_pubkey(pem)

          _ ->
            {:error, "Expected EC_SIGN_ED25519 algorithm, got: #{algorithm}"}
        end
      end
    end

    @doc """
    Alias for `public_key/1` (arg-spread form) — on Solana the public key is the
    address.
    """
    @spec get_address(term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, <<_::256>>} | {:error, term()}
    def get_address(cred, project, location, keychain, key, version) do
      public_key({cred, project, location, keychain, key, version})
    end

    @doc """
    Sign raw message bytes via a KMS Ed25519 key — the pure-payload contract.

    Ed25519 signs raw message bytes (no external hashing). The message is
    sent to KMS via the `data` field (not `digest`).

    Returns `{:ok, signature}` where signature is exactly 64 bytes.
    """
    @impl true
    @spec sign_payload(binary(), config()) :: {:ok, <<_::512>>} | {:error, term()}
    def sign_payload(message, {cred, project, location, keychain, key, version}) when is_binary(message) do
      name = key_version_name(project, location, keychain, key, version)

      with {:ok, %{"signature" => signature}} <-
             asymmetric_sign(credential_token(cred), name, %{data: Base.encode64(message)}),
           {:ok, <<signature::binary-64>>} <- Base.decode64(signature) do
        {:ok, signature}
      end
    end

    @doc """
    Back-compat alias for `sign_payload/2` (arg-spread form).
    """
    @spec sign(binary(), term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, <<_::512>>} | {:error, term()}
    def sign(message, cred, project, location, keychain, key, version) when is_binary(message) do
      sign_payload(message, {cred, project, location, keychain, key, version})
    end

    @spec key_version_name(String.t(), String.t(), String.t(), String.t(), String.t() | non_neg_integer()) ::
            String.t()
    defp key_version_name(project, location, keychain, key, version) do
      "projects/#{project}/locations/#{location}/keyRings/#{keychain}" <>
        "/cryptoKeys/#{key}/cryptoKeyVersions/#{version}"
    end

    @spec extract_ed25519_pubkey(binary()) :: {:ok, <<_::256>>} | {:error, String.t()}
    defp extract_ed25519_pubkey(pem) do
      [pem_entry] = :public_key.pem_decode(pem)
      {_type, der_bytes, _} = pem_entry

      case der_bytes do
        <<@ed25519_der_prefix, public_key::binary-32>> ->
          {:ok, public_key}

        _ ->
          {:error, "Unexpected DER format for Ed25519 public key"}
      end
    end

    @spec get_public_key(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
    defp get_public_key(token, name), do: request(token, :get, "#{name}/publicKey")

    @spec asymmetric_sign(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
    defp asymmetric_sign(token, name, body), do: request(token, :post, "#{name}:asymmetricSign", json: body)

    @spec request(String.t(), atom(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
    defp request(token, method, path, options \\ []) do
      [
        method: method,
        url: "#{@kms_base_url}/#{path}",
        auth: {:bearer, token},
        retry: false
      ]
      |> Keyword.merge(req_options())
      |> Req.request(options)
      |> normalize_response()
    end

    @spec normalize_response({:ok, Req.Response.t()} | {:error, Exception.t()}) :: {:ok, map()} | {:error, term()}
    defp normalize_response({:ok, %Req.Response{status: status, body: body}}) when status >= 200 and status < 300 do
      {:ok, body}
    end

    defp normalize_response({:ok, %Req.Response{} = response}), do: {:error, response}
    defp normalize_response({:error, exception}), do: {:error, Exception.message(exception)}

    @spec credential_token(term()) :: String.t()
    defp credential_token(token) when is_binary(token), do: token

    defp credential_token(cred) do
      %{token: token, type: "Bearer"} = Goth.fetch!(cred)
      token
    end

    @spec req_options() :: Keyword.t()
    defp req_options, do: :cartouche |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])
  end
end

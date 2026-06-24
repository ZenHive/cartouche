if Code.ensure_loaded?(Goth) do
  defmodule Cartouche.Signer.CloudKMS do
    @moduledoc """
    Signer backend that signs with a Google Cloud KMS secp256k1 key.

    Implements `Cartouche.Signer.Backend` — its `config` is the
    `{credentials, project, location, keychain, key, version}` key-coordinate
    tuple. `c:Cartouche.Signer.Backend.sign_payload/2` sends the 32-byte digest
    to KMS directly (no internal keccak); `sign/7` is a back-compat wrapper that
    keccaks a raw message first.
    """
    @behaviour Cartouche.Signer.Backend

    import Cartouche.Hash, only: [keccak: 1]

    @kms_base_url "https://cloudkms.googleapis.com/v1"

    @typedoc "Cloud KMS key coordinates: `{credentials, project, location, keychain, key, version}`."
    @type config :: {term(), String.t(), String.t(), String.t(), String.t(), String.t()}

    @impl true
    @spec algorithm(config()) :: :secp256k1
    def algorithm(_config), do: :secp256k1

    @doc """
    Get the uncompressed secp256k1 public key for the given KMS key version.
    """
    @impl true
    @spec public_key(config()) :: {:ok, binary()} | {:error, term()}
    def public_key({cred, project, location, keychain, key, version}) do
      name = key_version_name(project, location, keychain, key, version)

      with {:ok, %{"algorithm" => algorithm, "pem" => pem}} <- get_public_key(credential_token(cred), name) do
        case algorithm do
          "EC_SIGN_SECP256K1_SHA256" ->
            [certs] = :public_key.pem_decode(pem)
            {{:ECPoint, public_key}, _} = :public_key.pem_entry_decode(certs)
            {:ok, public_key}

          _ ->
            {:error, "Invalid algorithm: #{algorithm}"}
        end
      end
    end

    @doc ~S"""
    Get the Ethereum address associated with the given KMS key version.

    ## Examples

        iex> {:ok, address} = Cartouche.Signer.CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")
        iex> Cartouche.Hex.to_hex(address)
        "0xdda641b2a76a4a7c3617815bb13281dd207b74d5"
    """
    @spec get_address(term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, binary()} | {:error, term()}
    def get_address(cred, project, location, keychain, key, version) do
      with {:ok, pub} <- public_key({cred, project, location, keychain, key, version}) do
        {:ok, Cartouche.Address.from_public_key(pub)}
      end
    end

    @doc """
    Signs the 32-byte digest it is handed directly via KMS — the pure-payload
    contract. Performs no hashing; the caller owns digest computation.
    """
    @impl true
    @spec sign_payload(binary(), config()) :: {:ok, Curvy.Signature.t()} | {:error, term()}
    def sign_payload(digest, {cred, project, location, keychain, key, version}) when is_binary(digest) do
      name = key_version_name(project, location, keychain, key, version)

      with {:ok, %{"signature" => signature}} <-
             asymmetric_sign(credential_token(cred), name, %{digest: %{sha256: Base.encode64(digest)}}),
           {:ok, decoded_sig} <- Base.decode64(signature) do
        {:ok, Curvy.Signature.parse(decoded_sig)}
      end
    end

    @doc ~S"""
    Signs a raw message via KMS, keccak-digesting it first.

    Back-compat convenience over `sign_payload/2`.

    ## Examples

        iex> use Cartouche.Hex
        iex> {:ok, sig} = Cartouche.Signer.CloudKMS.sign("test", "token", "project", "location", "keychain", "key", "version")
        iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0xDDA641B2A76A4A7C3617815BB13281DD207B74D5])
        iex> Cartouche.Recover.recover_eth("test", %{sig|recid: recid}) |> Hex.to_address()
        "0xDDa641B2A76a4A7c3617815bb13281DD207b74d5"
    """
    @spec sign(String.t(), term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, Curvy.Signature.t()} | {:error, term()}
    def sign(message, cred, project, location, keychain, key, version) when is_binary(message) do
      sign_payload(keccak(message), {cred, project, location, keychain, key, version})
    end

    @spec key_version_name(String.t(), String.t(), String.t(), String.t(), String.t() | non_neg_integer()) ::
            String.t()
    defp key_version_name(project, location, keychain, key, version) do
      "projects/#{project}/locations/#{location}/keyRings/#{keychain}" <>
        "/cryptoKeys/#{key}/cryptoKeyVersions/#{version}"
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

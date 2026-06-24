if Code.ensure_loaded?(GoogleApi.CloudKMS.V1.Api.Projects) do
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

    alias GoogleApi.CloudKMS.V1.Api.Projects, as: CloudKMSApi
    alias GoogleApi.CloudKMS.V1.Connection

    @typedoc "Cloud KMS key coordinates: `{credentials, project, location, keychain, key, version}`."
    @type config :: {term(), String.t(), String.t(), String.t(), String.t(), String.t()}

    @impl true
    @spec algorithm(config()) :: :secp256k1
    def algorithm(_config), do: :secp256k1

    @doc """
    Get the uncompressed secp256k1 public key for the given KMS key version.
    """
    @impl true
    @spec public_key(config()) :: {:ok, binary()} | {:error, String.t()}
    def public_key({cred, project, location, keychain, key, version}) do
      name = key_version_name(project, location, keychain, key, version)

      with {:ok, %GoogleApi.CloudKMS.V1.Model.PublicKey{algorithm: algorithm, pem: pem}} <-
             CloudKMSApi.cloudkms_projects_locations_key_rings_crypto_keys_crypto_key_versions_get_public_key(
               client(cred),
               name
             ) do
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
            {:ok, binary()} | {:error, String.t()}
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
    @spec sign_payload(binary(), config()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
    def sign_payload(digest, {cred, project, location, keychain, key, version}) when is_binary(digest) do
      digest_enc = Base.encode64(digest)
      name = key_version_name(project, location, keychain, key, version)

      with {:ok, response} <-
             CloudKMSApi.cloudkms_projects_locations_key_rings_crypto_keys_crypto_key_versions_asymmetric_sign(
               client(cred),
               name,
               body: %{
                 digest: %{
                   sha256: digest_enc
                 }
               }
             ),
           {:ok, decoded_sig} <- Base.decode64(response.signature) do
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
            {:ok, Curvy.Signature.t()} | {:error, String.t()}
    def sign(message, cred, project, location, keychain, key, version) when is_binary(message) do
      sign_payload(keccak(message), {cred, project, location, keychain, key, version})
    end

    @spec key_version_name(String.t(), String.t(), String.t(), String.t(), String.t() | non_neg_integer()) ::
            String.t()
    defp key_version_name(project, location, keychain, key, version) do
      "projects/#{project}/locations/#{location}/keyRings/#{keychain}" <>
        "/cryptoKeys/#{key}/cryptoKeyVersions/#{version}"
    end

    # TODO: Tesla.Env.client() — Tesla is in plt_ignore_apps (OOM workaround), so dialyzer can't resolve the type
    @spec client(binary() | atom() | pid()) :: term()
    defp client(token) when is_binary(token), do: Connection.new(token)

    defp client(cred) do
      %{token: token, type: "Bearer"} = Goth.fetch!(cred)
      Connection.new(token)
    end
  end
end

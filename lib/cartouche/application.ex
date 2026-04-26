defmodule Cartouche.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @doc false
  def chain_id, do: Cartouche.Chain.parse_id(Application.get_env(:cartouche, :chain_id, 1))

  @doc false
  def ethereum_node, do: Application.get_env(:cartouche, :ethereum_node, "https://mainnet.infura.io")

  @doc false
  def http_client, do: Application.get_env(:cartouche, :client, Finch)

  @impl true
  def start(_type, _args) do
    eth_signers = Application.get_env(:cartouche, :signer, [])
    sol_signers = Application.get_env(:cartouche, :solana_signer, [])

    finch_name = Application.get_env(:cartouche, :finch_name, CartoucheFinch)
    # start a finch process by default
    finch_child =
      if Application.get_env(:cartouche, :start_finch, true) do
        [{Finch, name: finch_name}]
      else
        []
      end

    children =
      Enum.map(eth_signers, &get_signer_spec/1) ++
        Enum.map(sol_signers, &get_solana_signer_spec/1) ++
        finch_child

    opts = [strategy: :one_for_one, name: Cartouche.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # --- Ethereum signers ---

  @doc false
  def get_signer_spec({name, signer_type}) do
    name =
      case name do
        :default -> Cartouche.Signer.Default
        els -> els
      end

    Supervisor.child_spec(
      {Cartouche.Signer, mfa: signer_mfa(signer_type), name: name},
      id: name
    )
  end

  defp signer_mfa({:priv_key, priv_key}) do
    {Cartouche.Signer.Curvy, :sign, [Cartouche.Hex.decode_hex_input!(priv_key)]}
  end

  defp signer_mfa({:cloud_kms, kms_credentials, key_path, version}) do
    # E.g. "projects/*/locations/*/keyRings/*/cryptoKeys/*"

    ["projects", project, "locations", location, "keyRings", key_ring, "cryptoKeys", key_id] =
      String.split(key_path, "/")

    {Cartouche.Signer.CloudKMS, :sign, [kms_credentials, project, location, key_ring, key_id, version]}
  end

  # --- Solana signers ---

  defp get_solana_signer_spec({name, signer_type}) do
    name =
      case name do
        :default -> Cartouche.Solana.Signer.Default
        els -> els
      end

    Supervisor.child_spec(
      {Cartouche.Solana.Signer, mfa: solana_signer_mfa(signer_type), name: name},
      id: name
    )
  end

  defp solana_signer_mfa({:ed25519, seed}) do
    {Cartouche.Solana.Signer.Ed25519, :sign, [decode_solana_key!(seed)]}
  end

  defp solana_signer_mfa({:cloud_kms, kms_credentials, key_path, version}) do
    ["projects", project, "locations", location, "keyRings", key_ring, "cryptoKeys", key_id] =
      String.split(key_path, "/")

    {Cartouche.Solana.Signer.CloudKMS, :sign, [kms_credentials, project, location, key_ring, key_id, version]}
  end

  # Solana keys can be raw 32-byte binaries, hex-encoded, or Base58-encoded
  defp decode_solana_key!(key) when byte_size(key) == 32, do: key

  defp decode_solana_key!(key) when is_binary(key) do
    case Base.decode16(key, case: :mixed) do
      {:ok, <<decoded::binary-32>>} ->
        decoded

      _ ->
        case Cartouche.Base58.decode(key) do
          {:ok, <<decoded::binary-32>>} -> decoded
          _ -> Cartouche.Hex.decode_hex_input!(key)
        end
    end
  end
end

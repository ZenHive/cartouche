defmodule Cartouche.Recover do
  @moduledoc """
  EIP-191 (`personal_sign`) signature recovery primitives.

  Given a message and a 65-byte secp256k1 signature, recover the signer's
  public key (`recover_public_key/2`) or Ethereum address (`recover_eth/2`).
  When the signature arrived without a recovery bit (e.g. some HSM / KMS
  backends return only `(r, s)`), `find_recid/3` brute-forces the two valid
  recids against an expected address.

  Signatures may be supplied either as a `Curvy.Signature` struct (when the
  recovery bit lives in `:recid`) or as the raw 65-byte
  `<<r::256, s::256, v::8>>` form. The `v` byte is interpreted as recid `0`/`1`
  (raw form), `27`/`28` (`personal_sign`), or `35 + 2 * chain_id + recid`
  (EIP-155).

  Used internally by `Cartouche.Signer` for the recover-and-verify sanity check
  after each sign call, and exposed as the public surface for consumers
  verifying user-supplied signatures (e.g. `personal_sign` payloads from
  MetaMask, WalletConnect, or any wallet implementing EIP-191).
  """

  use Cartouche.Hex

  import Cartouche.Address, only: [from_public_key: 1]
  import Cartouche.Hash, only: [keccak: 1]

  @spec decode_signature(Curvy.Signature.t() | String.t() | <<_::520>>) :: Curvy.Signature.t() | :invalid_hex
  defp decode_signature(%Curvy.Signature{} = s), do: s

  defp decode_signature("0x" <> _signature_hex = signature) do
    with {:ok, signature_bytes} <- Hex.decode_hex(signature) do
      decode_signature(signature_bytes)
    end
  end

  defp decode_signature(<<r::integer-size(256), s::integer-size(256), v::integer-size(8)>>),
    do: %Curvy.Signature{
      crv: :secp256k1,
      r: r,
      s: s,
      recid:
        if v in [0, 1] do
          v
        else
          rem(v + 1, 2)
        end
    }

  @doc """
  Wraps a message in the EIP-191 `personal_sign` envelope.

  The returned binary concatenates four parts:

    * `0x19` — the EIP-191 version byte
    * `"Ethereum Signed Message:\\n"` — the literal namespace prefix (newline-terminated)
    * the byte length of `msg`, formatted as decimal ASCII
    * `msg` itself

  The doctest output below shows `\\x19` and `\\n` as escape sequences — those
  are the literal `0x19` byte and `0x0A` newline byte in the returned string.

  See [EIP-191](https://eips.ethereum.org/EIPS/eip-191).

  ## Examples

    iex> Cartouche.Recover.prefix_eth("hello")
    "\x19Ethereum Signed Message:\\n5hello"
  """
  @spec prefix_eth(String.t()) :: String.t()
  def prefix_eth(msg), do: "\x19Ethereum Signed Message:\n" <> to_string(String.length(msg)) <> msg

  @doc """
  Recovers a signer's public key from a signed message. The message will be
  digested by keccak first. Note: the rec_id can be embeded in the signature
  or passed separately.

  ## Examples

    iex> use Cartouche.Hex
    iex> # Decoded Signature
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> Cartouche.Recover.recover_public_key("test", %{sig|recid: recid}) |> to_hex()
    "0x0480076bfb96955526052b2676dfca87e0b7869ce85e00c5dbce29e76b8429d6dbf0f33b1a0095b2a9a4d9ea2a9746b122995a5b5874ee3161138c9d19f072b2d9"

    iex> use Cartouche.Hex
    iex> # Binary Signature
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> signature = <<sig.r::256, sig.s::256, recid>>
    iex> Cartouche.Recover.recover_public_key("test", signature) |> to_hex()
    "0x0480076bfb96955526052b2676dfca87e0b7869ce85e00c5dbce29e76b8429d6dbf0f33b1a0095b2a9a4d9ea2a9746b122995a5b5874ee3161138c9d19f072b2d9"

    iex> use Cartouche.Hex
    iex> # EIP-155 Signature
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> recovery_bit = 35 + 5 * 2 + recid
    iex> signature = <<sig.r::256, sig.s::256, recovery_bit::8>>
    iex> Cartouche.Recover.recover_public_key("test", signature) |> to_hex()
    "0x0480076bfb96955526052b2676dfca87e0b7869ce85e00c5dbce29e76b8429d6dbf0f33b1a0095b2a9a4d9ea2a9746b122995a5b5874ee3161138c9d19f072b2d9"
  """
  @spec recover_public_key(binary(), Curvy.Signature.t() | binary()) :: binary()
  def recover_public_key(message, signature) do
    signature
    |> decode_signature()
    |> Curvy.recover_key(keccak(message), hash: :keccak)
    |> Curvy.Key.to_pubkey(compressed: false)
  end

  @doc """
  Recovers a signer's Ethereum address from a signed message. The message will
  be digested by keccak first. Note: the rec_id can be embeded in the signature
  or passed separately.

  ## Examples

    iex> use Cartouche.Hex
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> Cartouche.Recover.recover_eth("test", %{sig|recid: recid})
    ...> |> to_hex()
    "0x63cc7c25e0cdb121abb0fe477a6b9901889f99a7"
  """
  @spec recover_eth(binary(), Curvy.Signature.t() | binary()) :: <<_::160>>
  def recover_eth(message, signature) do
    message
    |> recover_public_key(signature)
    |> from_public_key()
  end

  @doc """
  Finds the given recid which recovers the given signature for the message to the given
  Ethereum address. This is a very simple guess-check-revise since there are only four
  possible values, and we only accept two of those.

  ## Examples

    iex> use Cartouche.Hex
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> Cartouche.Recover.recover_eth("test", %{sig|recid: recid})
    ...> |> to_hex()
    "0x63cc7c25e0cdb121abb0fe477a6b9901889f99a7"
  """
  @spec find_recid(binary(), Curvy.Signature.t(), <<_::160>>) ::
          {:ok, 0..1} | {:error, String.t()}
  def find_recid(message, signature, address) do
    recid =
      Enum.find(0..3, fn recid ->
        Cartouche.Recover.recover_eth(message, %{signature | recid: recid}) == address
      end)

    case recid do
      nil ->
        {:error, "unable to recover to address #{Hex.encode_hex(address)}"}

      x when x > 1 ->
        {:error, "too high recovery bit #{recid}"}

      _ ->
        {:ok, recid}
    end
  end
end

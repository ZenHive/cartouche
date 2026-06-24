defmodule Cartouche.Transaction.TypedDecode do
  @moduledoc """
  Shared EIP-2718 typed-transaction envelope dispatch.

  Every typed transaction (EIP-2930 `V_2930`, EIP-7702 `V4`, …) decodes the
  same way: match the leading type byte, RLP-decode the remaining payload, then
  hand the decoded field list to a type-specific `decode_fields` callback. This
  module owns that envelope contract so each decoder only declares its type
  byte, its error message, and how to turn the RLP list into its struct.
  """

  @doc """
  Dispatches a typed-transaction binary.

  Matches the leading `tx_type` byte, RLP-decodes the rest (returning `invalid`
  on malformed RLP), and applies `decode_fields` to the decoded field list. Any
  other leading byte (or non-binary) yields `{:error, invalid}`.
  """
  @spec decode(binary(), byte(), String.t(), (list() -> {:ok, term()} | {:error, String.t()})) ::
          {:ok, term()} | {:error, String.t()}
  def decode(<<tx_type, trx_enc::binary>>, tx_type, invalid, decode_fields) do
    with {:ok, fields} <- safe_rlp_decode(trx_enc, invalid) do
      decode_fields.(fields)
    end
  end

  def decode(_, _tx_type, invalid, _decode_fields), do: {:error, invalid}

  @spec safe_rlp_decode(binary(), String.t()) :: {:ok, list()} | {:error, String.t()}
  defp safe_rlp_decode(trx_enc, invalid) do
    {:ok, ExRLP.decode(trx_enc)}
  rescue
    # ExRLP raises DecodeError on most malformed input, but leaks a MatchError
    # on truncated length-prefixed binaries (an internal `<<_::size>> = tail`).
    _e in [ExRLP.DecodeError, MatchError] -> {:error, invalid}
  end
end

defmodule Cartouche.Transaction.Signature do
  @moduledoc """
  Shared signature-field helpers for typed-transaction structs that carry the
  `signature_y_parity` / `signature_r` / `signature_s` triple
  (EIP-1559 `V2`, EIP-4844 `V3`, and any future post-EIP-2718 type).

  These functions operate on the struct as a plain map, so they work uniformly
  across the typed-transaction modules without coupling them to one another.
  """

  @doc """
  Attaches explicit signature fields (`y_parity`, `r`, `s`) to a transaction
  struct. `r` and `s` must be exactly 32 bytes and `v` a boolean y-parity.
  """
  @spec add(map(), boolean(), <<_::256>>, <<_::256>>) :: map()
  def add(transaction, v, <<_::256>> = r, <<_::256>> = s) when is_boolean(v) do
    %{transaction | signature_y_parity: v, signature_r: r, signature_s: s}
  end

  @doc """
  Recovers the packed `r <> s <> y_parity` signature from a signed transaction,
  or `{:error, "transaction missing signature"}` when any signature field is nil.
  """
  @spec get(map()) :: {:ok, binary()} | {:error, String.t()}
  def get(%{signature_y_parity: v, signature_r: r, signature_s: s}) when is_nil(v) or is_nil(r) or is_nil(s),
    do: {:error, "transaction missing signature"}

  def get(%{signature_y_parity: v, signature_r: r, signature_s: s}) do
    v_enc = :binary.encode_unsigned(if v, do: 1, else: 0)
    {:ok, <<r::binary-size(32), s::binary-size(32), v_enc::binary>>}
  end

  @doc """
  Attaches a packed `r <> s <> v` signature to a transaction struct.
  """
  @spec add_packed(map(), <<_::512, _::_*8>>) :: map()
  def add_packed(transaction, <<r::binary-size(32), s::binary-size(32), v_bin::binary>>) when byte_size(v_bin) > 0 do
    add(transaction, y_parity_from_v(v_bin), r, s)
  end

  @doc """
  Derives EIP-155-style y-parity from a packed recovery `v` byte sequence.
  """
  @spec y_parity_from_v(binary()) :: boolean()
  def y_parity_from_v(v_bin) do
    v = :binary.decode_unsigned(v_bin)
    if v < 2, do: v == 1, else: rem(v, 2) == 0
  end
end

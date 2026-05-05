defmodule Cartouche.Transaction.V3 do
  @moduledoc ~S"""
  Represents a V3 or EIP-4844 blob transaction.

  This module encodes the execution-layer transaction envelope only. Blob
  sidecars (blobs, KZG commitments, and KZG proofs) are propagated separately
  and are not part of the canonical signed transaction bytes.

  ## Examples

      iex> tx =
      ...>   Cartouche.Transaction.V3.new(
      ...>     1,
      ...>     {1, :gwei},
      ...>     {100, :gwei},
      ...>     100_000,
      ...>     <<1::160>>,
      ...>     {2, :wei},
      ...>     <<1, 2, 3>>,
      ...>     [],
      ...>     {1, :wei},
      ...>     [<<1, 0::248>>],
      ...>     :goerli
      ...>   )
      ...> tx = Cartouche.Transaction.V3.add_signature(tx, true, <<0x01::256>>, <<0x02::256>>)
      iex> {:ok, decoded} = tx |> Cartouche.Transaction.V3.encode() |> Cartouche.Transaction.V3.decode()
      iex> decoded == tx
      true
  """

  alias Cartouche.Signer.Default

  @type access_list :: [{<<_::160>>, [<<_::256>>]}]

  @type t :: %__MODULE__{
          chain_id: integer(),
          nonce: integer(),
          max_priority_fee_per_gas: integer(),
          max_fee_per_gas: integer(),
          gas_limit: integer(),
          destination: <<_::160>>,
          amount: integer(),
          data: binary(),
          access_list: access_list(),
          max_fee_per_blob_gas: integer(),
          blob_versioned_hashes: [<<_::256>>],
          signature_y_parity: boolean() | nil,
          signature_r: <<_::256>> | nil,
          signature_s: <<_::256>> | nil
        }

  defstruct [
    :chain_id,
    :nonce,
    :max_priority_fee_per_gas,
    :max_fee_per_gas,
    :gas_limit,
    :destination,
    :amount,
    :data,
    :access_list,
    :max_fee_per_blob_gas,
    :blob_versioned_hashes,
    :signature_y_parity,
    :signature_r,
    :signature_s
  ]

  @doc ~S"""
  Constructs a new V3 (EIP-4844) Ethereum transaction.
  """
  @spec new(
          integer(),
          integer() | {integer(), :wei | :gwei} | nil,
          integer() | {integer(), :wei | :gwei} | nil,
          integer(),
          <<_::160>>,
          integer() | {integer(), :wei | :gwei},
          binary(),
          access_list(),
          integer() | {integer(), :wei | :gwei} | nil,
          [<<_::256>>],
          atom() | integer() | nil
        ) :: t()
  def new(
        nonce,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        destination,
        amount,
        data,
        access_list,
        max_fee_per_blob_gas,
        blob_versioned_hashes,
        chain_id \\ nil
      ) do
    %__MODULE__{
      chain_id: chain_id_value(chain_id),
      nonce: nonce,
      max_priority_fee_per_gas: maybe_to_wei(max_priority_fee_per_gas),
      max_fee_per_gas: maybe_to_wei(max_fee_per_gas),
      gas_limit: gas_limit,
      destination: destination,
      amount: Cartouche.Wei.to_wei(amount),
      data: data,
      access_list: access_list,
      max_fee_per_blob_gas: maybe_to_wei(max_fee_per_blob_gas),
      blob_versioned_hashes: blob_versioned_hashes,
      signature_y_parity: nil,
      signature_r: nil,
      signature_s: nil
    }
  end

  @doc ~S"""
  Build an EIP-2718 typed RLP-encoded blob transaction.

  If any signature field is `nil`, the encoded payload omits
  `signature_y_parity`, `signature_r`, and `signature_s` and can be used as the
  signing preimage.
  """
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = transaction) do
    <<0x03>> <>
      (transaction
       |> rlp_payload()
       |> ExRLP.encode())
  end

  @doc """
  Decode a signed EIP-4844 blob transaction envelope.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(<<0x03, trx_enc::binary>>) do
    case ExRLP.decode(trx_enc) do
      [
        chain_id,
        nonce,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        destination,
        amount,
        data,
        access_list,
        max_fee_per_blob_gas,
        blob_versioned_hashes,
        signature_y_parity,
        signature_r,
        signature_s
      ] ->
        decode_payload([
          chain_id,
          nonce,
          max_priority_fee_per_gas,
          max_fee_per_gas,
          gas_limit,
          destination,
          amount,
          data,
          access_list,
          max_fee_per_blob_gas,
          blob_versioned_hashes,
          signature_y_parity,
          signature_r,
          signature_s
        ])

      _ ->
        {:error, "invalid v3 transaction"}
    end
  end

  def decode(_), do: {:error, "invalid v3 transaction"}

  @doc """
  Signs a V3 transaction with the given signer process.
  """
  @spec sign(t(), GenServer.name()) :: {:ok, t()} | {:error, String.t()}
  def sign(%__MODULE__{} = transaction, signer \\ Default) do
    unsigned = %{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil}

    with {:ok, signature} <- Cartouche.Signer.sign(encode(unsigned), signer, chain_id: transaction.chain_id) do
      {:ok, add_signature(transaction, signature)}
    end
  end

  @doc """
  Hashes the typed transaction bytes.
  """
  @spec hash(t()) :: <<_::256>>
  def hash(%__MODULE__{} = transaction), do: transaction |> encode() |> Cartouche.Hash.keccak()

  @doc """
  Adds explicit signature fields to a transaction.
  """
  @spec add_signature(t(), boolean(), <<_::256>>, <<_::256>>) :: t()
  def add_signature(%__MODULE__{} = transaction, v, <<_::256>> = r, <<_::256>> = s) when is_boolean(v) do
    %{transaction | signature_y_parity: v, signature_r: r, signature_s: s}
  end

  @doc """
  Adds a signature to a transaction from a packed binary (`r <> s <> v`).
  """
  @spec add_signature(t(), <<_::512, _::_*8>>) :: t()
  def add_signature(%__MODULE__{} = transaction, <<r::binary-size(32), s::binary-size(32), v_bin::binary>>) do
    add_signature(transaction, y_parity(v_bin), r, s)
  end

  @doc """
  Recovers a signature from a transaction, if it has been signed.
  """
  @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
  def get_signature(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s})
      when is_nil(v) or is_nil(r) or is_nil(s),
      do: {:error, "transaction missing signature"}

  def get_signature(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s}) do
    v_enc = :binary.encode_unsigned(if v, do: 1, else: 0)
    {:ok, <<r::binary-size(32), s::binary-size(32), v_enc::binary>>}
  end

  @doc """
  Recovers the signer from a signed V3 transaction.
  """
  @spec recover_signer(t()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_signer(%__MODULE__{} = transaction) do
    unsigned = %{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil}

    with {:ok, signature} <- get_signature(transaction) do
      {:ok, Cartouche.Recover.recover_eth(encode(unsigned), signature)}
    end
  end

  @spec chain_id_value(atom() | integer() | nil) :: integer()
  defp chain_id_value(nil), do: Cartouche.Application.chain_id()
  defp chain_id_value(chain_id), do: Cartouche.Chain.parse_id(chain_id)

  @spec maybe_to_wei(integer() | {integer(), :wei | :gwei} | nil) :: integer() | nil
  defp maybe_to_wei(nil), do: nil
  defp maybe_to_wei(value), do: Cartouche.Wei.to_wei(value)

  @spec rlp_payload(t()) :: list()
  defp rlp_payload(%__MODULE__{} = transaction) do
    base_payload(transaction) ++ signature_payload(transaction)
  end

  @spec base_payload(t()) :: list()
  defp base_payload(%__MODULE__{} = transaction) do
    [
      transaction.chain_id,
      transaction.nonce,
      transaction.max_priority_fee_per_gas,
      transaction.max_fee_per_gas,
      transaction.gas_limit,
      transaction.destination,
      transaction.amount,
      transaction.data,
      encode_access_list(transaction.access_list),
      transaction.max_fee_per_blob_gas,
      transaction.blob_versioned_hashes
    ]
  end

  @spec signature_payload(t()) :: list()
  defp signature_payload(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s})
       when is_nil(v) or is_nil(r) or is_nil(s),
       do: []

  defp signature_payload(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s}) do
    [if(v, do: 1, else: 0), trim_signature_word(r), trim_signature_word(s)]
  end

  @spec encode_access_list(access_list()) :: list()
  defp encode_access_list(access_list) do
    Enum.map(access_list, fn {address, storage} -> [address, storage] end)
  end

  @spec trim_signature_word(<<_::256>>) :: binary()
  defp trim_signature_word(signature_word), do: String.trim_leading(signature_word, <<0>>)

  @spec decode_payload([term()]) :: {:ok, t()} | {:error, String.t()}
  defp decode_payload([
         chain_id,
         nonce,
         max_priority_fee_per_gas,
         max_fee_per_gas,
         gas_limit,
         destination,
         amount,
         data,
         access_list,
         max_fee_per_blob_gas,
         blob_versioned_hashes,
         signature_y_parity,
         signature_r,
         signature_s
       ]) do
    with true <- byte_size(destination) == 20,
         true <- signature_word?(signature_r),
         true <- signature_word?(signature_s),
         {:ok, access_list} <- decode_access_list(access_list),
         {:ok, blob_versioned_hashes} <- decode_blob_versioned_hashes(blob_versioned_hashes) do
      {:ok,
       %__MODULE__{
         chain_id: :binary.decode_unsigned(chain_id),
         nonce: :binary.decode_unsigned(nonce),
         max_priority_fee_per_gas: :binary.decode_unsigned(max_priority_fee_per_gas),
         max_fee_per_gas: :binary.decode_unsigned(max_fee_per_gas),
         gas_limit: :binary.decode_unsigned(gas_limit),
         destination: destination,
         amount: :binary.decode_unsigned(amount),
         data: data,
         access_list: access_list,
         max_fee_per_blob_gas: :binary.decode_unsigned(max_fee_per_blob_gas),
         blob_versioned_hashes: blob_versioned_hashes,
         signature_y_parity: :binary.decode_unsigned(signature_y_parity) == 1,
         signature_r: Cartouche.Hex.pad(signature_r, 32),
         signature_s: Cartouche.Hex.pad(signature_s, 32)
       }}
    else
      _ -> {:error, "invalid v3 transaction"}
    end
  end

  @spec signature_word?(binary()) :: boolean()
  defp signature_word?(word), do: byte_size(word) <= 32

  @spec decode_access_list(list()) :: {:ok, access_list()} | {:error, String.t()}
  defp decode_access_list(access_list) do
    {:ok,
     Enum.map(access_list, fn
       [address, storage] when byte_size(address) <= 20 ->
         {Cartouche.Hex.pad(address, 20), Enum.map(storage, &Cartouche.Hex.pad(&1, 32))}
     end)}
  rescue
    FunctionClauseError -> {:error, "invalid v3 transaction"}
  end

  @spec decode_blob_versioned_hashes(list()) :: {:ok, [<<_::256>>]} | {:error, String.t()}
  defp decode_blob_versioned_hashes(blob_versioned_hashes) do
    if Enum.all?(blob_versioned_hashes, &(byte_size(&1) == 32)) do
      {:ok, blob_versioned_hashes}
    else
      {:error, "invalid v3 transaction"}
    end
  end

  @spec y_parity(binary()) :: boolean()
  defp y_parity(v_bin) do
    v = :binary.decode_unsigned(v_bin)

    if v < 2 do
      v == 1
    else
      rem(v, 2) == 0
    end
  end
end

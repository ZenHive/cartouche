defmodule Cartouche.Transaction.V4 do
  @moduledoc ~S"""
  Represents a V4 or EIP-7702 set-code transaction.

  EIP-7702 transactions use transaction type `0x04` and extend the EIP-1559
  field set with an authorization list. Each authorization entry is a
  `{chain_id, address, nonce, y_parity, r, s}` tuple signed over
  `0x05 || rlp([chain_id, address, nonce])`.

  ## Examples

      iex> use Cartouche.Hex
      iex> authorization = {
      ...>   1,
      ...>   ~h[0x0000000000000000000000000000000000000002],
      ...>   7,
      ...>   false,
      ...>   <<1::256>>,
      ...>   <<2::256>>
      ...> }
      iex> transaction =
      ...>   Cartouche.Transaction.V4.new(
      ...>     1,
      ...>     {1, :gwei},
      ...>     {100, :gwei},
      ...>     100_000,
      ...>     ~h[0x0000000000000000000000000000000000000001],
      ...>     {2, :wei},
      ...>     <<1, 2, 3>>,
      ...>     [],
      ...>     [authorization],
      ...>     :mainnet
      ...>   )
      ...>   |> Cartouche.Transaction.V4.add_signature(<<3::256, 4::256, 0>>)
      iex> {:ok, decoded} = transaction |> Cartouche.Transaction.V4.encode() |> Cartouche.Transaction.V4.decode()
      iex> decoded == transaction
      true
  """

  alias Cartouche.Signer.Default

  @type authorization :: {
          non_neg_integer(),
          <<_::160>>,
          non_neg_integer(),
          boolean() | nil,
          <<_::256>> | nil,
          <<_::256>> | nil
        }

  @type unsigned_authorization :: {non_neg_integer(), <<_::160>>, non_neg_integer()}

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          gas_limit: non_neg_integer(),
          destination: <<_::160>>,
          amount: non_neg_integer(),
          data: binary(),
          access_list: [{<<_::160>>, [<<_::256>>]}],
          authorization_list: [authorization()],
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
    :authorization_list,
    :signature_y_parity,
    :signature_r,
    :signature_s
  ]

  @type tx_input ::
          t()
          | %__MODULE__{
              chain_id: non_neg_integer() | nil,
              nonce: non_neg_integer() | nil,
              max_priority_fee_per_gas: non_neg_integer() | nil,
              max_fee_per_gas: non_neg_integer() | nil,
              gas_limit: non_neg_integer() | nil,
              destination: <<_::160>> | nil,
              amount: non_neg_integer() | nil,
              data: binary() | nil,
              access_list: list() | nil,
              authorization_list: list() | nil,
              signature_y_parity: nil,
              signature_r: nil,
              signature_s: nil
            }

  @tx_type 0x04
  @authorization_magic 0x05
  @invalid "invalid v4 transaction"

  @doc """
  Constructs an unsigned EIP-7702 transaction.
  """
  @spec new(
          non_neg_integer(),
          non_neg_integer() | {non_neg_integer(), :wei | :gwei} | nil,
          non_neg_integer() | {non_neg_integer(), :wei | :gwei} | nil,
          non_neg_integer(),
          <<_::160>>,
          non_neg_integer() | {non_neg_integer(), :wei | :gwei},
          binary(),
          list(),
          [authorization()],
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
        authorization_list,
        chain_id \\ nil
      ) do
    %__MODULE__{
      chain_id: parse_chain_id(chain_id),
      nonce: nonce,
      max_priority_fee_per_gas: maybe_to_wei(max_priority_fee_per_gas),
      max_fee_per_gas: maybe_to_wei(max_fee_per_gas),
      gas_limit: gas_limit,
      destination: destination,
      amount: Cartouche.Wei.to_wei(amount),
      data: data,
      access_list: access_list,
      authorization_list: authorization_list,
      signature_y_parity: nil,
      signature_r: nil,
      signature_s: nil
    }
  end

  @doc """
  Build an RLP-encoded EIP-7702 transaction.
  """
  @spec encode(tx_input()) :: binary()
  def encode(%__MODULE__{} = transaction) do
    <<@tx_type>> <> ExRLP.encode(encoded_fields(transaction))
  end

  @doc """
  Decode an RLP-encoded EIP-7702 transaction.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(<<@tx_type, trx_enc::binary>>) do
    with {:ok, fields} <- safe_rlp_decode(trx_enc),
         {:ok, transaction} <- decode_fields(fields) do
      {:ok, transaction}
    else
      _ -> {:error, @invalid}
    end
  end

  def decode(_), do: {:error, @invalid}

  @doc """
  Signs the outer EIP-7702 transaction.
  """
  @spec sign(t(), GenServer.name()) :: {:ok, t()} | {:error, String.t()}
  def sign(%__MODULE__{} = transaction, signer \\ Default) do
    with {:ok, signature} <- Cartouche.Signer.sign(signing_payload(transaction), signer, chain_id: transaction.chain_id) do
      {:ok, add_signature(transaction, signature)}
    end
  end

  @doc """
  Returns the transaction hash for signed or unsigned encoded bytes.
  """
  @spec hash(t() | binary()) :: <<_::256>>
  def hash(%__MODULE__{} = transaction), do: transaction |> encode() |> Cartouche.Hash.keccak()
  def hash(<<@tx_type, _::binary>> = encoded), do: Cartouche.Hash.keccak(encoded)

  @doc """
  Returns the outer transaction signing payload.
  """
  @spec signing_payload(t()) :: binary()
  def signing_payload(%__MODULE__{} = transaction) do
    encode(%{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil})
  end

  @doc """
  Adds an outer transaction signature from a packed binary (`r <> s <> v`).
  """
  @spec add_signature(t(), <<_::512, _::_*8>>) :: t()
  def add_signature(%__MODULE__{} = transaction, <<r::binary-size(32), s::binary-size(32), v_bin::binary>>) do
    %{transaction | signature_y_parity: signature_y_parity(v_bin), signature_r: r, signature_s: s}
  end

  @doc """
  Recovers the signer from a signed EIP-7702 transaction.
  """
  @spec recover_signer(t()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_signer(%__MODULE__{} = transaction) do
    with {:ok, signature} <- get_signature(transaction) do
      {:ok, Cartouche.Recover.recover_eth(signing_payload(transaction), signature)}
    end
  end

  @doc """
  Recovers a packed outer transaction signature (`r <> s <> y_parity`).
  """
  @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
  def get_signature(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s})
      when is_nil(v) or is_nil(r) or is_nil(s),
      do: {:error, "transaction missing signature"}

  def get_signature(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s}) do
    {:ok, r <> s <> <<y_parity_integer(v)>>}
  end

  @doc """
  Signs an EIP-7702 authorization tuple.
  """
  @spec sign_authorization(unsigned_authorization(), GenServer.name()) ::
          {:ok, authorization()} | {:error, String.t()}
  def sign_authorization({chain_id, address, nonce} = authorization, signer \\ Default) do
    with {:ok, signature} <-
           Cartouche.Signer.sign(authorization_signing_payload(authorization), signer, chain_id: chain_id) do
      {:ok, add_authorization_signature({chain_id, address, nonce, nil, nil, nil}, signature)}
    end
  end

  @doc """
  Returns the EIP-7702 authorization signing payload.
  """
  @spec authorization_signing_payload(unsigned_authorization() | authorization()) :: binary()
  def authorization_signing_payload(authorization) do
    {chain_id, address, nonce} = authorization_core(authorization)
    <<@authorization_magic>> <> ExRLP.encode([chain_id, address, nonce])
  end

  @doc """
  Returns the EIP-7702 authorization signing hash.
  """
  @spec authorization_hash(unsigned_authorization() | authorization()) :: <<_::256>>
  def authorization_hash(authorization), do: authorization |> authorization_signing_payload() |> Cartouche.Hash.keccak()

  @doc """
  Adds an authorization signature from a packed binary (`r <> s <> v`).
  """
  @spec add_authorization_signature(authorization(), <<_::512, _::_*8>>) :: authorization()
  def add_authorization_signature(
        {chain_id, address, nonce, _v, _r, _s},
        <<r::binary-size(32), s::binary-size(32), v_bin::binary>>
      ) do
    {chain_id, address, nonce, signature_y_parity(v_bin), r, s}
  end

  @doc """
  Recovers the EOA that signed an authorization tuple.
  """
  @spec recover_authority(authorization()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_authority(authorization) do
    with {:ok, signature} <- get_authorization_signature(authorization) do
      {:ok, Cartouche.Recover.recover_eth(authorization_signing_payload(authorization), signature)}
    end
  end

  @doc """
  Returns a packed authorization signature (`r <> s <> y_parity`).
  """
  @spec get_authorization_signature(authorization()) :: {:ok, binary()} | {:error, String.t()}
  def get_authorization_signature({_chain_id, _address, _nonce, v, r, s}) when is_nil(v) or is_nil(r) or is_nil(s),
    do: {:error, "authorization missing signature"}

  def get_authorization_signature({_chain_id, _address, _nonce, v, r, s}) do
    {:ok, r <> s <> <<y_parity_integer(v)>>}
  end

  @spec encoded_fields(tx_input()) :: list()
  defp encoded_fields(%__MODULE__{
         chain_id: chain_id,
         nonce: nonce,
         max_priority_fee_per_gas: max_priority_fee_per_gas,
         max_fee_per_gas: max_fee_per_gas,
         gas_limit: gas_limit,
         destination: destination,
         amount: amount,
         data: data,
         access_list: access_list,
         authorization_list: authorization_list,
         signature_y_parity: signature_y_parity,
         signature_r: signature_r,
         signature_s: signature_s
       }) do
    [
      chain_id,
      nonce,
      max_priority_fee_per_gas,
      max_fee_per_gas,
      gas_limit,
      destination,
      amount,
      data,
      encode_access_list(access_list),
      Enum.map(authorization_list, &encode_authorization/1)
    ] ++ encode_signature_fields(signature_y_parity, signature_r, signature_s)
  end

  @spec encode_access_list([{<<_::160>>, [<<_::256>>]}] | nil) :: list()
  defp encode_access_list(nil), do: []

  defp encode_access_list(access_list) do
    Enum.map(access_list, fn {address, storage} -> [address, storage] end)
  end

  @spec encode_authorization(authorization()) :: list()
  defp encode_authorization({chain_id, address, nonce, y_parity, r, s}) do
    [
      chain_id,
      address,
      nonce,
      y_parity_integer(y_parity),
      String.trim_leading(r, <<0>>),
      String.trim_leading(s, <<0>>)
    ]
  end

  @spec encode_signature_fields(boolean() | nil, binary() | nil, binary() | nil) :: list()
  defp encode_signature_fields(y_parity, r, s) when is_nil(y_parity) or is_nil(r) or is_nil(s), do: []

  defp encode_signature_fields(y_parity, r, s) do
    [y_parity_integer(y_parity), String.trim_leading(r, <<0>>), String.trim_leading(s, <<0>>)]
  end

  @spec decode_fields(list()) :: {:ok, t()} | {:error, String.t()}
  defp decode_fields([
         chain_id,
         nonce,
         max_priority_fee_per_gas,
         max_fee_per_gas,
         gas_limit,
         destination,
         amount,
         data,
         access_list,
         authorization_list,
         signature_y_parity,
         signature_r,
         signature_s
       ]) do
    with {:ok, chain_id} <- decode_uint(chain_id, 32),
         {:ok, nonce} <- decode_uint(nonce, 8),
         {:ok, max_priority_fee_per_gas} <- decode_uint(max_priority_fee_per_gas, 32),
         {:ok, max_fee_per_gas} <- decode_uint(max_fee_per_gas, 32),
         {:ok, gas_limit} <- decode_uint(gas_limit, 8),
         {:ok, amount} <- decode_uint(amount, 32),
         {:ok, access_list} <- decode_access_list(access_list),
         {:ok, authorization_list} <- decode_authorization_list(authorization_list),
         {:ok, destination} <- decode_address(destination),
         {:ok, signature_y_parity} <- decode_y_parity(signature_y_parity),
         {:ok, signature_r} <- decode_word(signature_r),
         {:ok, signature_s} <- decode_word(signature_s) do
      {:ok,
       %__MODULE__{
         chain_id: chain_id,
         nonce: nonce,
         max_priority_fee_per_gas: max_priority_fee_per_gas,
         max_fee_per_gas: max_fee_per_gas,
         gas_limit: gas_limit,
         destination: destination,
         amount: amount,
         data: data,
         access_list: access_list,
         authorization_list: authorization_list,
         signature_y_parity: signature_y_parity,
         signature_r: signature_r,
         signature_s: signature_s
       }}
    else
      _ -> {:error, @invalid}
    end
  end

  defp decode_fields(_), do: {:error, @invalid}

  @spec decode_access_list(list()) :: {:ok, [{<<_::160>>, [<<_::256>>]}]} | {:error, String.t()}
  defp decode_access_list(access_list) when is_list(access_list) do
    access_list
    |> Enum.reduce_while({:ok, []}, &decode_access_entry/2)
    |> reverse_ok()
  end

  defp decode_access_list(_), do: {:error, @invalid}

  @spec decode_access_entry(term(), {:ok, list()}) :: {:cont, {:ok, list()}} | {:halt, {:error, String.t()}}
  defp decode_access_entry([address, storage], {:ok, entries}) when is_list(storage) do
    with {:ok, address} <- decode_address(address),
         {:ok, storage} <- decode_storage_keys(storage) do
      {:cont, {:ok, [{address, storage} | entries]}}
    else
      _ -> {:halt, {:error, @invalid}}
    end
  end

  defp decode_access_entry(_, _acc), do: {:halt, {:error, @invalid}}

  @spec decode_storage_keys(list()) :: {:ok, [<<_::256>>]} | {:error, String.t()}
  defp decode_storage_keys(storage) do
    storage
    |> Enum.reduce_while({:ok, []}, &decode_storage_key/2)
    |> reverse_ok()
  end

  @spec decode_storage_key(term(), {:ok, list()}) :: {:cont, {:ok, list()}} | {:halt, {:error, String.t()}}
  defp decode_storage_key(storage_key, {:ok, storage}) do
    case decode_exact_binary(storage_key, 32) do
      {:ok, storage_key} -> {:cont, {:ok, [storage_key | storage]}}
      {:error, _} -> {:halt, {:error, @invalid}}
    end
  end

  @spec decode_authorization_list(list()) :: {:ok, [authorization()]} | {:error, String.t()}
  defp decode_authorization_list(authorization_list) when is_list(authorization_list) do
    authorization_list
    |> Enum.reduce_while({:ok, []}, &decode_authorization_entry/2)
    |> reverse_ok()
  end

  defp decode_authorization_list(_), do: {:error, @invalid}

  @spec decode_authorization_entry(term(), {:ok, list()}) :: {:cont, {:ok, list()}} | {:halt, {:error, String.t()}}
  defp decode_authorization_entry([chain_id, address, nonce, y_parity, r, s], {:ok, authorizations}) do
    with {:ok, chain_id} <- decode_uint(chain_id, 32),
         {:ok, nonce} <- decode_uint(nonce, 8),
         {:ok, address} <- decode_address(address),
         {:ok, y_parity} <- decode_y_parity(y_parity),
         {:ok, r} <- decode_word(r),
         {:ok, s} <- decode_word(s) do
      authorization = {chain_id, address, nonce, y_parity, r, s}
      {:cont, {:ok, [authorization | authorizations]}}
    else
      _ -> {:halt, {:error, @invalid}}
    end
  end

  defp decode_authorization_entry(_, _acc), do: {:halt, {:error, @invalid}}

  @spec decode_address(binary()) :: {:ok, <<_::160>>} | {:error, String.t()}
  defp decode_address(address), do: decode_exact_binary(address, 20)

  @spec decode_word(binary()) :: {:ok, <<_::256>>} | {:error, String.t()}
  defp decode_word(word) when byte_size(word) <= 32, do: {:ok, Cartouche.Hex.pad(word, 32)}
  defp decode_word(_), do: {:error, @invalid}

  @spec decode_exact_binary(binary(), pos_integer()) :: {:ok, binary()} | {:error, String.t()}
  defp decode_exact_binary(value, size) when byte_size(value) == size, do: {:ok, value}
  defp decode_exact_binary(_, _size), do: {:error, @invalid}

  @spec decode_y_parity(binary()) :: {:ok, boolean()} | {:error, String.t()}
  defp decode_y_parity(y_parity) do
    case decode_uint(y_parity, 1) do
      {:ok, 0} -> {:ok, false}
      {:ok, 1} -> {:ok, true}
      _ -> {:error, @invalid}
    end
  end

  @spec decode_uint(binary(), pos_integer()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  defp decode_uint(value, max_bytes) when is_binary(value) and byte_size(value) <= max_bytes do
    {:ok, :binary.decode_unsigned(value)}
  end

  defp decode_uint(_, _max_bytes), do: {:error, @invalid}

  @spec maybe_to_wei(non_neg_integer() | {non_neg_integer(), :wei | :gwei} | nil) :: non_neg_integer() | nil
  defp maybe_to_wei(nil), do: nil
  defp maybe_to_wei(value), do: Cartouche.Wei.to_wei(value)

  @spec parse_chain_id(atom() | integer() | nil) :: integer()
  defp parse_chain_id(nil), do: Cartouche.Application.chain_id()
  defp parse_chain_id(chain_id), do: Cartouche.Chain.parse_id(chain_id)

  @spec safe_rlp_decode(binary()) :: {:ok, term()} | {:error, String.t()}
  defp safe_rlp_decode(bytes) do
    {:ok, ExRLP.decode(bytes)}
  rescue
    _ -> {:error, @invalid}
  end

  @spec reverse_ok({:ok, list()} | {:error, String.t()}) :: {:ok, list()} | {:error, String.t()}
  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok({:error, _} = error), do: error

  @spec signature_y_parity(binary()) :: boolean()
  defp signature_y_parity(v_bin) do
    v = :binary.decode_unsigned(v_bin)
    if v < 2, do: v == 1, else: rem(v, 2) == 0
  end

  @spec y_parity_integer(boolean() | nil) :: 0 | 1
  defp y_parity_integer(true), do: 1
  defp y_parity_integer(false), do: 0

  @spec authorization_core(unsigned_authorization() | authorization()) :: unsigned_authorization()
  defp authorization_core({chain_id, address, nonce}), do: {chain_id, address, nonce}
  defp authorization_core({chain_id, address, nonce, _y_parity, _r, _s}), do: {chain_id, address, nonce}
end

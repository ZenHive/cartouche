# credo:disable-for-this-file Credo.Check.Readability.ModuleNames
defmodule Cartouche.Transaction.V_2930 do
  @moduledoc ~S"""
  Represents a type-1 EIP-2930 access-list transaction.
  """

  alias Cartouche.Transaction.JsonField
  alias Cartouche.Transaction.TypedDecode

  @type access_list :: [{<<_::160>>, [<<_::256>>]}]

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          gas_price: non_neg_integer(),
          gas_limit: non_neg_integer(),
          destination: <<_::160>> | nil,
          amount: non_neg_integer(),
          data: binary(),
          access_list: access_list(),
          signature_y_parity: boolean() | nil,
          signature_r: <<_::256>> | nil,
          signature_s: <<_::256>> | nil
        }

  defstruct [
    :chain_id,
    :nonce,
    :gas_price,
    :gas_limit,
    :destination,
    :amount,
    :data,
    :access_list,
    :signature_y_parity,
    :signature_r,
    :signature_s
  ]

  @tx_type 0x01
  @invalid "invalid v2930 transaction"

  @doc """
  Decodes an EIP-2930 typed RLP transaction.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(input), do: TypedDecode.decode(input, @tx_type, @invalid, &decode_fields/1)

  @doc ~S"""
  Decodes an EIP-2930 (type 1) transaction object from block JSON-RPC.
  """
  @spec from_json(map()) :: t() | no_return()
  def from_json(%{} = params) do
    %__MODULE__{
      chain_id: Cartouche.Hex.decode_hex_number!(params["chainId"]),
      nonce: Cartouche.Hex.decode_hex_number!(params["nonce"]),
      gas_price: Cartouche.Hex.decode_hex_number!(params["gasPrice"]),
      gas_limit: Cartouche.Hex.decode_hex_number!(params["gas"]),
      destination: JsonField.decode_destination(params["to"]),
      amount: Cartouche.Hex.decode_hex_number!(params["value"]),
      data: Cartouche.Hex.decode_hex!(params["input"]),
      access_list: JsonField.decode_access_list(params["accessList"]),
      signature_y_parity: JsonField.decode_y_parity(params),
      signature_r: JsonField.decode_signature_word(params["r"]),
      signature_s: JsonField.decode_signature_word(params["s"])
    }
  end

  @spec decode_fields(term()) :: {:ok, t()} | {:error, String.t()}
  defp decode_fields([_, _, _, _, _, _, _, _] = fields) do
    decode_payload(fields, {nil, nil, nil})
  end

  defp decode_fields([
         chain_id,
         nonce,
         gas_price,
         gas_limit,
         destination,
         amount,
         data,
         access_list,
         signature_y_parity,
         signature_r,
         signature_s
       ]) do
    with {:ok, signature_y_parity} <- TypedDecode.decode_y_parity(signature_y_parity, @invalid),
         {:ok, signature_r} <- TypedDecode.decode_word(signature_r, @invalid),
         {:ok, signature_s} <- TypedDecode.decode_word(signature_s, @invalid) do
      decode_payload(
        [chain_id, nonce, gas_price, gas_limit, destination, amount, data, access_list],
        {signature_y_parity, signature_r, signature_s}
      )
    else
      _ -> {:error, @invalid}
    end
  end

  defp decode_fields(_), do: {:error, @invalid}

  @spec decode_payload(
          [term()],
          {boolean() | nil, <<_::256>> | nil, <<_::256>> | nil}
        ) :: {:ok, t()} | {:error, String.t()}
  defp decode_payload(
         [chain_id, nonce, gas_price, gas_limit, destination, amount, data, access_list],
         {signature_y_parity, signature_r, signature_s}
       )
       when is_binary(data) do
    with true <- byte_size(destination) == 20,
         {:ok, access_list} <- TypedDecode.decode_access_list(access_list, @invalid) do
      {:ok,
       %__MODULE__{
         chain_id: :binary.decode_unsigned(chain_id),
         nonce: :binary.decode_unsigned(nonce),
         gas_price: :binary.decode_unsigned(gas_price),
         gas_limit: :binary.decode_unsigned(gas_limit),
         destination: destination,
         amount: :binary.decode_unsigned(amount),
         data: data,
         access_list: access_list,
         signature_y_parity: signature_y_parity,
         signature_r: signature_r,
         signature_s: signature_s
       }}
    else
      _ -> {:error, @invalid}
    end
  rescue
    # `:binary.decode_unsigned/1` and `byte_size/1` raise ArgumentError on the
    # non-binary terms a malformed RLP payload can yield; helpers return
    # `{:error, …}` rather than raising.
    ArgumentError -> {:error, @invalid}
  end

  defp decode_payload(_, _), do: {:error, @invalid}
end

defmodule Cartouche.Transaction.Call do
  @moduledoc """
  Represents Ethereum `eth_call` parameters, not a signable or broadcastable transaction.

  `destination` is required because generated contract calls always target a deployed contract.
  `data` is required because generated contract calls execute ABI-encoded calldata.
  `from` is optional because `eth_call` accepts a caller address but existing RPC callers pass it through options.
  `gas` is optional because `eth_call` can cap execution gas without creating a transaction gas limit.
  `value` is optional because `eth_call` can simulate payable execution without transferring funds.
  Fee, nonce, chain-id, access-list, and signature fields are excluded because calls are never signed or broadcast.
  """

  @type t :: %__MODULE__{
          destination: <<_::160>>,
          data: binary(),
          from: <<_::160>> | nil,
          gas: non_neg_integer() | nil,
          value: non_neg_integer() | nil
        }

  defstruct [:destination, :data, :from, :gas, :value]

  @doc """
  Builds an `eth_call` parameter struct.
  """
  @spec new(<<_::160>>, binary(), Keyword.t()) :: t()
  def new(destination, data, opts \\ []) when is_binary(data) do
    # Validate destination is 20 bytes (160 bits)
    unless byte_size(destination) == 20 do
      raise ArgumentError,
            "destination must be a 20-byte binary, got #{byte_size(destination)} bytes"
    end

    # Extract optional parameters
    from = Keyword.get(opts, :from)
    gas = Keyword.get(opts, :gas)
    value = Keyword.get(opts, :value)

    # Validate from address if present
    if from != nil and byte_size(from) != 20 do
      raise ArgumentError, "from must be a 20-byte binary, got #{byte_size(from)} bytes"
    end

    # Validate gas if present
    if gas != nil and (not is_integer(gas) or gas < 0) do
      raise ArgumentError, "gas must be a non-negative integer, got #{inspect(gas)}"
    end

    # Validate value if present
    if value != nil and (not is_integer(value) or value < 0) do
      raise ArgumentError, "value must be a non-negative integer, got #{inspect(value)}"
    end

    %__MODULE__{
      destination: destination,
      data: data,
      from: from,
      gas: gas,
      value: value
    }
  end
end

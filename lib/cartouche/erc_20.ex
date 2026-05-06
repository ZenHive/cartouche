defmodule Cartouche.Erc20 do
  @moduledoc """
  A wrapper for an [ERC-20 contract](https://eips.ethereum.org/EIPS/eip-20),
  allowing the code to interact by pulling data from the contract, or sending
  transaction to it.
  """

  @type call_opts() :: Keyword.t()
  @type exec_opts() :: Keyword.t()

  @errors []

  @doc ~S"""
  Returns a list of known error codes (ABI signatures), which can be used
  when parsing error messages from contract calls.
  """
  @spec errors() :: [String.t()]
  def errors, do: @errors

  @doc ~S"""
  Executes a transaction against the given ERC-20 token, using the provided
  ABI-encoded `call_data`. The configured Cartouche signer signs and submits
  the transaction; `exec_opts` is forwarded to `Cartouche.RPC.execute_trx/3`
  with this module's known error signatures merged in.
  """
  @spec exec_trx(Cartouche.contract(), binary(), exec_opts()) :: term()
  def exec_trx(token, call_data, exec_opts) do
    Cartouche.RPC.execute_trx(
      Cartouche.get_contract_address(token),
      call_data,
      Keyword.put_new(exec_opts, :errors, errors())
    )
  end

  @doc ~S"""
  Performs an `eth_call` against the given ERC-20 token with the provided
  ABI-encoded `call_data` and zero value/gas. Returns the call's return data
  without sending a transaction. `call_opts` is forwarded to
  `Cartouche.RPC.call_trx/2` with this module's known error signatures
  merged in.
  """
  @spec call_trx(Cartouche.contract(), binary(), call_opts()) :: term()
  def call_trx(token, call_data, call_opts) do
    token
    |> Cartouche.get_contract_address()
    |> Cartouche.Transaction.build_trx(0, call_data, 0, 0, 0)
    |> Cartouche.RPC.call_trx(Keyword.put_new(call_opts, :errors, errors()))
  end

  defmodule CallData do
    @moduledoc """
    Module to encode `calldata` for given adaptor operations.
    """

    @doc ~S"""
    Encodes the call data for a `balanceOf` operation.

    ## Examples

        iex> Cartouche.Erc20.CallData.balance_of(<<0xDD>>) |> Cartouche.Hex.encode_hex()
        "0x"
    """
    @spec balance_of(Cartouche.address()) :: binary()
    def balance_of(address) do
      ABI.encode("balanceOf(address)", [address])
    end

    @doc ~S"""
    Encodes the call data for a `transfer` operation.

    ## Examples

        iex> Cartouche.Erc20.CallData.transfer(<<0xDD>>, 100_000)
        ...> |> Cartouche.Hex.encode_hex()
        "0x8035f0ce"
    """
    @spec transfer(Cartouche.address(), non_neg_integer()) :: binary()
    def transfer(destination, amount_wei) do
      ABI.encode("transfer(address,uint256)", [destination, amount_wei])
    end
  end

  defmodule Call do
    @moduledoc """
    Module to call operations and receive return value, without sending a transaction.
    """

    @doc ~S"""
    Calls the `balanceOf` operation, returning the result of the Ethereum function call.

    ## Examples

        iex> Cartouche.Erc20.Call.balance_of(<<0xCC>>, <<0xDD>>)
        {:ok, <<>>}
    """
    @spec balance_of(Cartouche.contract(), Cartouche.address(), Cartouche.Erc20.call_opts()) ::
            {:ok, number()} | {:error, term()}
    def balance_of(token, address, call_opts \\ []) do
      call_opts = Keyword.put(call_opts, :decode, :hex_unsigned)
      Cartouche.Erc20.call_trx(token, CallData.balance_of(address), call_opts)
    end

    @doc ~S"""
    Calls the `transfer` operation, returning the result of the Ethereum function call.

    ## Examples

        iex> Cartouche.Erc20.Call.transfer(<<0xCC>>, <<0xDD>>, 100_000)
        {:ok, <<>>}
    """
    @spec transfer(
            Cartouche.contract(),
            Cartouche.address(),
            non_neg_integer(),
            Cartouche.Erc20.call_opts()
          ) :: {:ok, binary()} | {:error, term()}
    def transfer(token, destination, amount_wei, call_opts \\ []) do
      call_opts = Keyword.put(call_opts, :decode, :hex)
      Cartouche.Erc20.call_trx(token, CallData.transfer(destination, amount_wei), call_opts)
    end
  end

  @doc ~S"""
  Executes a `transfer` transaction.

  Arguments:
    - `destination`: The destination address
    - `amount_wei`: The amount, in token wei, to transfer.
    - `exec_opts`: Execution options, such as the gas price for the transaction.

  ## Examples

      iex> {:ok, _trx_id} = Cartouche.Erc20.transfer(<<0xCC::160>>, <<0xDD::160>>, 100_000)
  """
  @spec transfer(Cartouche.contract(), Cartouche.address(), non_neg_integer(), exec_opts()) ::
          {:ok, binary()} | {:error, term()}
  def transfer(token, destination, amount_wei, exec_opts \\ []) do
    exec_trx(token, CallData.transfer(destination, amount_wei), exec_opts)
  end
end

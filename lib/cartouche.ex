defmodule Cartouche do
  @moduledoc """
  Cartouche is a library for interacting with private keys, signatures, and Etheruem.
  """

  @type address :: <<_::160>>
  @type signature :: <<_::520>>
  @type bytes32 :: <<_::256>>
  @type contract :: address() | atom()

  @doc ~S"""
  Returns a contract address, that may have been set in configuration.

  ## Examples

      iex> Cartouche.get_contract_address(<<1::160>>)
      <<1::160>>

      iex> Cartouche.get_contract_address("0x0000000000000000000000000000000000000001")
      <<1::160>>

      iex> Application.put_env(:cartouche, :contracts, [test: "0x0000000000000000000000000000000000000001"])
      iex> Cartouche.get_contract_address(:test)
      <<1::160>>
  """
  @spec get_contract_address(binary() | atom()) :: address()
  def get_contract_address(address) when is_binary(address), do: Cartouche.Hex.decode_hex_input!(address)

  def get_contract_address(contract) when is_atom(contract) do
    :cartouche
    |> Application.get_env(:contracts, [])
    |> Keyword.fetch!(contract)
    |> Cartouche.Hex.decode_hex_input!()
  end
end

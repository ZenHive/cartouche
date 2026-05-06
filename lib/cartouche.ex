defmodule Cartouche do
  @moduledoc """
  Cartouche is a library for interacting with private keys, signatures, and Ethereum.

  ## API discovery

  Cartouche exposes a machine-readable API surface for AI agents and
  introspection tooling via [`descripex`](https://hexdocs.pm/descripex):

      Cartouche.describe()                  # registered modules + namespaces
      Cartouche.describe(:signer)            # function list for one module
      Cartouche.describe(:signer, :sign_direct)   # full param/return detail

  The registered module list is built up as Phase 12 lands; see
  `ROADMAP.md` Phase 12 for the annotation pass.
  """

  @descripex_modules [
    Cartouche.Signer,
    Cartouche.Keys,
    Cartouche.RPC,
    Cartouche.Block,
    Cartouche.Block.Withdrawal,
    Cartouche.Receipt,
    Cartouche.Receipt.Log,
    Cartouche.FeeHistory,
    Cartouche.DebugTrace,
    Cartouche.DebugTrace.StructLog,
    Cartouche.Trace,
    Cartouche.Trace.Action,
    Cartouche.TraceCall
  ]
  use Descripex.Discoverable, modules: @descripex_modules

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

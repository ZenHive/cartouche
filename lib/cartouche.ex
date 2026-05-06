defmodule Cartouche do
  @moduledoc """
  Cartouche is a library for interacting with private keys, signatures, and Ethereum.

  ## API discovery

  Cartouche exposes a machine-readable API surface for AI agents and
  introspection tooling via [`descripex`](https://hexdocs.pm/descripex):

      Cartouche.describe()                  # registered modules + namespaces
      Cartouche.describe(:signer)            # function list for one module
      Cartouche.describe(:signer, :sign_direct)   # full param/return detail
      Cartouche.describe(:transaction_v1)    # nested Transaction.V1 helpers
      Cartouche.describe(:transaction_v2)    # nested Transaction.V2 helpers

  The registered module list is built up as Phase 12 lands; see
  `ROADMAP.md` Phase 12 for the annotation pass.
  """

  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  @descripex_modules [
    Cartouche.Signer,
    Cartouche.Keys,
    Cartouche.Transaction,
    V1,
    V2,
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

  @type address :: <<_::160>>
  @type signature :: <<_::520>>
  @type bytes32 :: <<_::256>>
  @type contract :: address() | atom()

  @doc "Return a Level 1 overview of all modules in this library."
  @spec describe() :: [map()]
  def describe do
    @descripex_modules
    |> Descripex.Describe.describe()
    |> Enum.map(&normalize_descripex_summary/1)
  end

  @doc "Return Level 2 function list for a module (by full atom, short name, or Cartouche transaction alias)."
  @spec describe(module() | atom()) :: [map()]
  def describe(mod_or_short),
    do: Descripex.Describe.describe(@descripex_modules, normalize_descripex_module(mod_or_short))

  @doc "Return Level 3 function detail (or `nil` if not found)."
  @spec describe(module() | atom(), atom()) :: map() | nil
  def describe(mod_or_short, func_name) do
    module = normalize_descripex_module(mod_or_short)

    case Descripex.Describe.describe(@descripex_modules, module, func_name) do
      nil -> transaction_dispatch_detail(module, func_name)
      detail -> detail
    end
  end

  @doc "Return the list of modules registered with this library."
  @spec __descripex_modules__() :: [module()]
  def __descripex_modules__, do: @descripex_modules

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

  @spec normalize_descripex_module(module() | atom()) :: module() | atom()
  defp normalize_descripex_module(:transaction_v1), do: V1
  defp normalize_descripex_module(:transaction_v2), do: V2
  defp normalize_descripex_module(mod_or_short), do: mod_or_short

  @spec normalize_descripex_summary(map()) :: map()
  defp normalize_descripex_summary(%{module: V1} = summary), do: %{summary | short_name: :transaction_v1}
  defp normalize_descripex_summary(%{module: V2} = summary), do: %{summary | short_name: :transaction_v2}
  defp normalize_descripex_summary(summary), do: summary

  @spec transaction_dispatch_detail(module() | atom(), atom()) :: map() | nil
  defp transaction_dispatch_detail(:transaction, :encode) do
    %{
      name: :encode,
      arity: 1,
      defaults: 0,
      description: "Encode a concrete transaction struct using the matching versioned transaction module.",
      spec: nil,
      params: %{
        transaction: %{
          kind: :value,
          description:
            "%Cartouche.Transaction.V1{} or %Cartouche.Transaction.V2{}; use the versioned module for concrete encoding."
        }
      },
      opts: nil,
      returns: %{
        type: :transaction_binary,
        description:
          "RLP-encoded legacy binary for %Cartouche.Transaction.V1{} or `0x02`-prefixed typed RLP binary for %Cartouche.Transaction.V2{}."
      },
      returns_example: nil,
      errors: nil,
      composes_with: [:transaction_v1, :transaction_v2]
    }
  end

  defp transaction_dispatch_detail(_, _), do: nil
end

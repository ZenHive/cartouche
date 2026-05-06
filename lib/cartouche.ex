defmodule Cartouche do
  @moduledoc """
  Cartouche is a library for interacting with private keys, signatures, and Ethereum.

  ## API discovery

  Cartouche exposes a machine-readable API surface for AI agents and
  introspection tooling via [`descripex`](https://hexdocs.pm/descripex):

      Cartouche.describe()                  # registered modules + namespaces
      Cartouche.describe(:signer)            # function list for one module
      Cartouche.describe(:signer, :sign_direct)   # full param/return detail
      Cartouche.describe(:solana_rpc)        # Solana RPC helpers
      Cartouche.describe(:transaction_v1)    # nested Transaction.V1 helpers
      Cartouche.describe(:transaction_v2)    # nested Transaction.V2 helpers

  The registered module list is built up as Phase 12 lands; see
  `ROADMAP.md` Phase 12 for the annotation pass.
  """

  use Descripex, namespace: "/cartouche"

  alias Cartouche.Erc20.Call
  alias Cartouche.Erc20.CallData
  alias Cartouche.Solana.ATA
  alias Cartouche.Solana.Keys
  alias Cartouche.Solana.PDA
  alias Cartouche.Solana.Programs
  alias Cartouche.Solana.RPC
  alias Cartouche.Solana.Signer
  alias Cartouche.Solana.SystemProgram
  alias Cartouche.Solana.Token
  alias Cartouche.Solana.TokenProgram
  alias Cartouche.Solana.Transaction
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  @descripex_modules [
    Cartouche.Signer,
    Cartouche.Keys,
    Cartouche.Hex,
    Cartouche.Erc20,
    CallData,
    Call,
    Cartouche.Sleuth,
    Cartouche.Hash,
    Cartouche.Address,
    Cartouche.Wei,
    Cartouche.Chain,
    Cartouche.Base58,
    Cartouche.RecoveryBit,
    Signer,
    Transaction,
    Keys,
    PDA,
    ATA,
    Programs,
    SystemProgram,
    TokenProgram,
    Token,
    RPC,
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

  @descripex_aliases %{
    signer: Cartouche.Signer,
    keys: Cartouche.Keys,
    transaction: Cartouche.Transaction,
    transaction_v1: V1,
    transaction_v2: V2,
    erc20_call_data: CallData,
    erc20_call: Call,
    solana_signer: Signer,
    solana_transaction: Transaction,
    solana_keys: Keys,
    solana_pda: PDA,
    solana_ata: ATA,
    solana_programs: Programs,
    solana_system_program: SystemProgram,
    solana_token_program: TokenProgram,
    solana_token: Token,
    solana_rpc: RPC
  }

  @descripex_summary_names Map.new(@descripex_aliases, fn {short_name, module} -> {module, short_name} end)

  @type address :: <<_::160>>
  @type signature :: <<_::520>>
  @type bytes32 :: <<_::256>>
  @type contract :: address() | atom()

  api(:describe, "Describe Cartouche's registered API surface at progressive levels of detail.",
    params: [
      mod_or_short: [
        kind: :value,
        description: "Full module atom, Descripex short name, or Cartouche alias to drill into."
      ],
      func_name: [
        kind: :value,
        description: "Function name atom for Level 3 detail."
      ]
    ],
    returns: %{
      type: :list_or_map,
      description: "Level 1 module overview list, Level 2 function summary list, or Level 3 function detail map."
    },
    errors: [
      argument_error: "Raised when the requested module short name or alias cannot be resolved."
    ]
  )

  @doc "Return a Level 1 overview of all modules in this library."
  @spec describe() :: [map()]
  def describe do
    @descripex_modules
    |> Descripex.Describe.describe()
    |> Enum.map(&normalize_descripex_summary/1)
  end

  @doc "Return Level 2 function list for a module by full atom, Descripex short name, or Cartouche alias."
  @spec describe(module() | atom()) :: [map()]
  def describe(mod_or_short),
    do: Descripex.Describe.describe(@descripex_modules, normalize_descripex_module(mod_or_short))

  @doc "Return Level 3 function detail for a module by full atom, Descripex short name, or Cartouche alias."
  @spec describe(module() | atom(), atom()) :: map() | nil
  def describe(mod_or_short, func_name) do
    module = normalize_descripex_module(mod_or_short)

    case Descripex.Describe.describe(@descripex_modules, module, func_name) do
      nil -> transaction_dispatch_detail(module, func_name)
      detail -> detail
    end
  end

  @doc false
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
  defp normalize_descripex_module(module) when module in @descripex_modules, do: module

  defp normalize_descripex_module(short_or_alias) do
    Map.get(@descripex_aliases, short_or_alias, short_or_alias)
  end

  @spec normalize_descripex_summary(map()) :: map()
  defp normalize_descripex_summary(%{module: module} = summary) do
    case Map.fetch(@descripex_summary_names, module) do
      {:ok, short_name} -> %{summary | short_name: short_name}
      :error -> summary
    end
  end

  defp normalize_descripex_summary(summary), do: summary

  @spec transaction_dispatch_detail(module() | atom(), atom()) :: map() | nil
  defp transaction_dispatch_detail(Cartouche.Transaction, :encode) do
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

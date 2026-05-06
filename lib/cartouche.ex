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

  alias Cartouche.Solana.ATA
  alias Cartouche.Solana.Keys
  alias Cartouche.Solana.PDA
  alias Cartouche.Solana.Programs
  alias Cartouche.Solana.Signer
  alias Cartouche.Solana.SystemProgram
  alias Cartouche.Solana.Token
  alias Cartouche.Solana.TokenProgram
  alias Cartouche.Solana.Transaction

  @descripex_modules [
    Cartouche.Signer,
    Cartouche.Keys,
    Signer,
    Transaction,
    Keys,
    PDA,
    ATA,
    Programs,
    SystemProgram,
    TokenProgram,
    Token
  ]

  @descripex_aliases %{
    signer: Cartouche.Signer,
    keys: Cartouche.Keys,
    solana_signer: Signer,
    solana_transaction: Transaction,
    solana_keys: Keys,
    solana_pda: PDA,
    solana_ata: ATA,
    solana_programs: Programs,
    solana_system_program: SystemProgram,
    solana_token_program: TokenProgram,
    solana_token: Token
  }

  @type address :: <<_::160>>
  @type signature :: <<_::520>>
  @type bytes32 :: <<_::256>>
  @type contract :: address() | atom()

  @doc "Return a Level 1 overview of all modules in this library."
  @spec describe() :: [map()]
  def describe, do: Descripex.Describe.describe(@descripex_modules)

  @doc "Return Level 2 function list for a module by full atom, Descripex short name, or Cartouche alias."
  @spec describe(module() | atom()) :: [map()]
  def describe(mod_or_short), do: Descripex.Describe.describe(@descripex_modules, resolve_descripex_module(mod_or_short))

  @doc "Return Level 3 function detail for a module by full atom, Descripex short name, or Cartouche alias."
  @spec describe(module() | atom(), atom()) :: map() | nil
  def describe(mod_or_short, func_name) do
    Descripex.Describe.describe(@descripex_modules, resolve_descripex_module(mod_or_short), func_name)
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

  @spec resolve_descripex_module(module() | atom()) :: module() | atom()
  defp resolve_descripex_module(module) when module in @descripex_modules, do: module

  defp resolve_descripex_module(short_or_alias) do
    Map.get(@descripex_aliases, short_or_alias, short_or_alias)
  end
end

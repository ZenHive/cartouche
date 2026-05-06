defmodule Cartouche.DescripexValidationTest do
  use ExUnit.Case, async: false

  alias Cartouche.Solana.Transaction

  describe "Cartouche.__descripex_modules__/0" do
    test "every public function in a registered module carries descripex :hints metadata" do
      for module <- Cartouche.__descripex_modules__() do
        case Code.fetch_docs(module) do
          {:docs_v1, _, _, _, _, _, docs} ->
            for {{:function, name, arity}, _line, _sigs, doc, meta} <- docs, doc != :hidden do
              case meta[:hints] do
                %{description: description} when is_binary(description) and description != "" ->
                  :ok

                _ ->
                  flunk("""
                  #{inspect(module)}.#{name}/#{arity} is missing descripex :hints metadata.

                  Annotate the function with an `api(...)` block (see `agent-economy.md`),
                  or hide it from the public surface with `@doc false`.
                  """)
              end
            end

          {:error, reason} ->
            flunk("""
            Code.fetch_docs(#{inspect(module)}) returned {:error, #{inspect(reason)}}.

            The module is registered in Cartouche.__descripex_modules__/0 but appears
            uncompiled or stripped of doc chunks. Confirm it compiles cleanly and
            is not built with strip_beams: true / docs disabled.
            """)
        end
      end
    end

    test "returns a list (initially empty until Phase 12 annotation tasks register modules)" do
      assert is_list(Cartouche.__descripex_modules__())
    end

    test "describe/0 lists registered modules" do
      assert Enum.any?(Cartouche.describe(), &(&1.module == Transaction))
    end

    test "Solana modules resolve through explicit discovery aliases" do
      aliases = %{
        solana_signer: Cartouche.Solana.Signer,
        solana_transaction: Transaction,
        solana_keys: Cartouche.Solana.Keys,
        solana_pda: Cartouche.Solana.PDA,
        solana_ata: Cartouche.Solana.ATA,
        solana_programs: Cartouche.Solana.Programs,
        solana_system_program: Cartouche.Solana.SystemProgram,
        solana_token_program: Cartouche.Solana.TokenProgram,
        solana_token: Cartouche.Solana.Token
      }

      for {short_name, module} <- aliases do
        assert Cartouche.describe(short_name) == Cartouche.describe(module)
      end
    end

    test "Cartouche discovery functions carry descripex hints" do
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(Cartouche)

      for arity <- 0..2 do
        assert {{:function, :describe, ^arity}, _, _, _, %{hints: %{description: description}}} =
                 Enum.find(docs, fn
                   {{:function, :describe, doc_arity}, _, _, _, _} -> doc_arity == arity
                   _ -> false
                 end)

        assert description =~ "registered API surface"
      end
    end

    test "Solana discovery accepts full module atoms" do
      assert Cartouche.describe(Transaction) == Cartouche.describe(:solana_transaction)
    end

    test "Solana sign_partial metadata documents unsigned placeholder signatures" do
      detail = Cartouche.describe(:solana_transaction, :sign_partial)

      assert detail.returns.description =~ "placeholder signatures"
      assert detail.returns.description =~ "empty signer map"
    end

    test "Cartouche contract address helper handles binary and configured atom inputs" do
      address = "0x0000000000000000000000000000000000000001"
      previous_contracts = Application.get_env(:cartouche, :contracts)
      Application.put_env(:cartouche, :contracts, Keyword.put(previous_contracts || [], :test_descripex, address))

      on_exit(fn ->
        case previous_contracts do
          nil -> Application.delete_env(:cartouche, :contracts)
          contracts -> Application.put_env(:cartouche, :contracts, contracts)
        end
      end)

      assert <<1::160>> = Cartouche.get_contract_address(address)
      assert <<1::160>> = Cartouche.get_contract_address(:test_descripex)
    end
  end
end

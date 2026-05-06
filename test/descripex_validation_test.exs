defmodule Cartouche.DescripexValidationTest do
  use ExUnit.Case, async: true

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
      aliases = [
        :solana_signer,
        :solana_transaction,
        :solana_keys,
        :solana_pda,
        :solana_ata,
        :solana_programs,
        :solana_system_program,
        :solana_token_program,
        :solana_token
      ]

      for alias <- aliases do
        assert [%{name: _, description: description} | _] = Cartouche.describe(alias)
        assert is_binary(description)
        assert description != ""
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
      Application.put_env(:cartouche, :contracts, test_descripex: address)

      on_exit(fn -> Application.delete_env(:cartouche, :contracts) end)

      assert <<1::160>> = Cartouche.get_contract_address(address)
      assert <<1::160>> = Cartouche.get_contract_address(:test_descripex)
    end
  end
end

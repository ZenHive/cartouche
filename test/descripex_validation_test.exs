defmodule Cartouche.DescripexValidationTest do
  use ExUnit.Case, async: true

  describe "Cartouche.__descripex_modules__/0" do
    test "registers transaction modules for Phase 12 discovery" do
      assert Cartouche.Transaction in Cartouche.__descripex_modules__()
      assert Cartouche.Transaction.V1 in Cartouche.__descripex_modules__()
      assert Cartouche.Transaction.V2 in Cartouche.__descripex_modules__()
    end

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
  end

  describe "Cartouche.describe/1 transaction aliases" do
    test "exposes top-level transaction constructor helpers" do
      functions = Cartouche.describe(:transaction)

      assert Enum.any?(functions, &match?(%{name: :build_trx}, &1))
      assert Enum.any?(functions, &match?(%{name: :build_trx_v2}, &1))
    end

    test "exposes versioned transaction modules through stable nested aliases" do
      assert Enum.any?(Cartouche.describe(:transaction_v1), &match?(%{name: :encode}, &1))
      assert Enum.any?(Cartouche.describe(:transaction_v2), &match?(%{name: :encode}, &1))
    end

    test "exposes transaction encode guidance without adding a runtime dispatcher" do
      detail = Cartouche.describe(:transaction, :encode)

      assert %{
               params: %{transaction: %{kind: :value}},
               returns: %{type: :transaction_binary},
               description: description
             } = detail

      assert description =~ "matching versioned transaction module"
    end
  end
end

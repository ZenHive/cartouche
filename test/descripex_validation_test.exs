defmodule Cartouche.DescripexValidationTest do
  use ExUnit.Case, async: true

  describe "Cartouche.__descripex_modules__/0" do
    test "registers transaction modules for Phase 12 discovery" do
      assert Cartouche.Transaction in Cartouche.__descripex_modules__()
      assert Cartouche.Transaction.V1 in Cartouche.__descripex_modules__()
      assert Cartouche.Transaction.V2 in Cartouche.__descripex_modules__()
    end

    test "registers Solana RPC for Phase 12 discovery" do
      assert Cartouche.Solana.RPC in Cartouche.__descripex_modules__()
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

    test "exposes transaction encode guidance for module input" do
      detail = Cartouche.describe(Cartouche.Transaction, :encode)

      assert %{
               params: %{transaction: %{kind: :value}},
               returns: %{type: :transaction_binary},
               description: description
             } = detail

      assert description =~ "matching versioned transaction module"
    end

    test "keeps top-level transaction decode and build metadata aligned" do
      assert %{description: decode_description} = fetch_hints(Cartouche.Transaction, :decode, 1)
      assert decode_description =~ "Decode raw Ethereum transaction bytes"

      assert %{description: build_description} = fetch_hints(Cartouche.Transaction, :build_trx, 7)
      assert build_description =~ "Build a legacy transaction"
    end
  end

  describe "Cartouche.describe/1 Solana RPC alias" do
    test "exposes Solana RPC through a stable short alias" do
      assert Enum.any?(Cartouche.describe(:solana_rpc), &match?(%{name: :get_balance}, &1))
    end

    test "exposes Solana RPC function detail through a stable short alias" do
      assert %{
               description: description,
               params: %{pubkey: %{kind: :value}},
               returns: %{type: :ok_error_tuple}
             } = Cartouche.describe(:solana_rpc, :get_balance)

      assert description == "Get the SOL balance for an account."
    end
  end

  defp fetch_hints(module, function, arity) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    docs
    |> Enum.find_value(fn
      {{:function, ^function, ^arity}, _line, _sigs, _doc, meta} -> meta[:hints]
      _ -> nil
    end)
    |> tap(fn
      nil -> flunk("#{inspect(module)}.#{function}/#{arity} is missing docs metadata")
      _ -> :ok
    end)
  end
end

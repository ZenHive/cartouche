defmodule SleuthTest do
  use ExUnit.Case
  use Cartouche.Hex

  alias Cartouche.Contract.BlockNumber
  alias Cartouche.Sleuth

  defmodule StaticEthCallClient do
    @moduledoc false

    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      %{"id" => id} = Jason.decode!(body)
      result = Process.get(:sleuth_eth_call_result)
      response = Jason.encode!(%{"jsonrpc" => "2.0", "result" => result, "id" => id})

      {:ok, %Finch.Response{status: 200, body: response}}
    end
  end

  defmodule MissingFunsContract do
    @moduledoc false
    # Intentionally does not define bytecode/0, encode_query/0, or query_selector/0.
    # Used to exercise the try_apply rescue clause.
  end

  doctest Sleuth

  describe "try_apply rescue" do
    test "raises descriptive error when contract module is missing :bytecode/0" do
      assert_raise RuntimeError,
                   ~r/Sleuth module .*MissingFunsContract does not define required "bytecode\/0"/,
                   fn -> Sleuth.query_by(MissingFunsContract) end
    end
  end

  describe "generated Sleuth call shape" do
    test "build_trx_query/3 returns an eth_call struct instead of a partial V2 transaction" do
      call = Cartouche.Contract.Sleuth.build_trx_query(<<1::160>>, <<2, 3>>, <<4, 5>>)

      assert %Cartouche.Transaction.Call{destination: <<1::160>>, data: data} = call
      assert data == Cartouche.Contract.Sleuth.encode_query(<<2, 3>>, <<4, 5>>)
    end
  end

  describe "BlockNumber" do
    test "query_by/2 keyword form defaults to :query" do
      assert {:ok, %{"blockNumber" => 2}} == Sleuth.query_by(BlockNumber, named_returns: true)
    end

    test "query()" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query(),
          BlockNumber.query_selector(),
          opts
        )
      end

      assert {:ok, [2]} == v2_case.([])
      assert {:ok, [block_number: 2]} == v2_case.(named_returns: true)
    end

    test "query() failure with trace" do
      assert {:error,
              %{
                code: 3,
                message: "execution reverted",
                trace: _
              }} =
               Sleuth.query(
                 ~h[],
                 ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001],
                 BlockNumber.query_selector(),
                 trace_reverts: true
               )
    end

    test "query() failure with debug trace" do
      assert {:error,
              %{
                code: 3,
                message: "execution reverted",
                trace: _
              }} =
               Sleuth.query(
                 ~h[],
                 ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001],
                 BlockNumber.query_selector(),
                 trace_reverts: true,
                 debug_trace: true
               )
    end

    test "query_by() via mod/fun" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query_by(
                 BlockNumber,
                 :query
               )
    end

    test "query_by() via mod" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query_by(BlockNumber)
    end

    test "queryTwo()" do
      assert {:ok, %{"x" => 2, "y" => 3}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_two(),
                 BlockNumber.query_two_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_two(),
          BlockNumber.query_two_selector(),
          opts
        )
      end

      assert {:ok, [2, 3]} == v2_case.([])
      assert {:ok, [x: 2, y: 3]} == v2_case.(named_returns: true)
    end

    test "queryTwo() - annotated" do
      assert {:ok, %{"x" => {{:uint, 256}, 2}, "y" => {{:uint, 256}, 3}}} ==
               Sleuth.query_annotated(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_two(),
                 BlockNumber.query_two_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_two(),
          BlockNumber.query_two_selector(),
          opts
        )
      end

      assert {:ok, [{{:uint, 256}, 2}, {{:uint, 256}, 3}]} == v2_case.(annotated: true)

      assert {:ok, [x: {{:uint, 256}, 2}, y: {{:uint, 256}, 3}]} ==
               v2_case.(annotated: true, named_returns: true)
    end

    test "queryThree()" do
      assert {:ok, 2} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_three(),
                 BlockNumber.query_three_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_three(),
          BlockNumber.query_three_selector(),
          opts
        )
      end

      assert {:ok, [2]} == v2_case.([])
      assert {:ok, [__unnamed__: 2]} == v2_case.(named_returns: true)
    end

    test "queryThree() - annotated" do
      assert {:ok, {{:uint, 256}, 2}} ==
               Sleuth.query_annotated(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_three(),
                 BlockNumber.query_three_selector()
               )

      assert {:ok, [{{:uint, 256}, 2}]} ==
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_three(),
                 BlockNumber.query_three_selector(),
                 annotated: true
               )
    end

    test "queryFour()" do
      assert {:ok, %{"var0" => ~h[0x010203], "var1" => <<1::160>>}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_four(),
                 BlockNumber.query_four_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_four(),
          BlockNumber.query_four_selector(),
          opts
        )
      end

      assert {:ok, [~h[0x010203], <<1::160>>]} == v2_case.([])

      assert {:ok, [__unnamed__: ~h[0x010203], __unnamed__: <<1::160>>]} ==
               v2_case.(named_returns: true)
    end

    test "queryFour() - no decode binaries" do
      assert {:ok, %{"var0" => "0x010203", "var1" => "0x0000000000000000000000000000000000000001"}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_four(),
                 BlockNumber.query_four_selector(),
                 decode_binaries: false
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_four(),
          BlockNumber.query_four_selector(),
          opts
        )
      end

      assert {:ok, ["0x010203", "0x0000000000000000000000000000000000000001"]} ==
               v2_case.(decode_binaries: false)

      assert {:ok, [__unnamed__: "0x010203", __unnamed__: "0x0000000000000000000000000000000000000001"]} ==
               v2_case.(decode_binaries: false, named_returns: true)
    end

    test "queryCool()" do
      assert {:ok,
              %{
                "cool" => %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              }} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_cool(),
                 BlockNumber.query_cool_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_cool(),
          BlockNumber.query_cool_selector(),
          opts
        )
      end

      assert {:ok,
              [
                %{
                  fun: %{cat: "meow"},
                  x: "hi",
                  ys: [1, 2, 3]
                }
              ]} == v2_case.([])

      assert {:ok,
              [
                %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              ]} == v2_case.(decode_structs: false)

      assert {:ok,
              [
                cool: %{
                  fun: %{cat: "meow"},
                  x: "hi",
                  ys: [1, 2, 3]
                }
              ]} == v2_case.(named_returns: true)

      assert {:ok,
              [
                cool: %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              ]} == v2_case.(named_returns: true, decode_structs: false)
    end

    test "queryCool() - annotated" do
      assert {:ok,
              %{
                "cool" => %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              }} ==
               Sleuth.query_annotated(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_cool(),
                 BlockNumber.query_cool_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_cool(),
          BlockNumber.query_cool_selector(),
          opts
        )
      end

      assert {:ok,
              [
                %{
                  fun: %{cat: {:string, "meow"}},
                  x: {:string, "hi"},
                  ys: [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_case.(annotated: true)

      assert {:ok,
              [
                %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_case.(annotated: true, decode_structs: false)

      assert {:ok,
              [
                cool: %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_case.(annotated: true, decode_structs: false, named_returns: true)
    end
  end

  describe "decode failures and return postprocessing" do
    test "query_v2/4 pre-interns cold generated return-field atoms before struct decode" do
      suffix = System.unique_integer([:positive])
      module_name = Module.concat(Cartouche.Contract, "ColdLoadProbe#{suffix}")
      field_name = "coldLoadReturnField#{suffix}"
      field_atom_name = Macro.underscore(field_name)

      refute Code.loaded?(module_name)
      refute existing_atom?(field_atom_name)

      Code.compile_string("""
      defmodule #{inspect(module_name)} do
        def bytecode, do: <<>>
        def encode_query, do: <<>>

        def query_selector do
          %ABI.FunctionSelector{
            returns: [%{name: #{inspect(field_name)}, type: {:uint, 256}}]
          }
        end
      end
      """)

      assert Code.loaded?(module_name)
      refute existing_atom?(field_atom_name)

      selector = module_name.query_selector()
      set_sleuth_result(ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}))

      assert_raise ArgumentError, ~r/requires the snake_case field atom/, fn ->
        ABI.decode(
          %ABI.FunctionSelector{types: selector.returns},
          ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}),
          decode_structs: true
        )
      end

      refute existing_atom?(field_atom_name)

      assert {:ok, [{key, 7}]} =
               Sleuth.query_v2(
                 module_name.bytecode(),
                 module_name.encode_query(),
                 selector,
                 client: StaticEthCallClient,
                 named_returns: true
               )

      assert Atom.to_string(key) == field_atom_name
      assert existing_atom?(field_atom_name)
    end

    test "returns a decode-bytes error when the eth_call result is not ABI bytes" do
      Process.put(:sleuth_eth_call_result, "0x1234")

      assert {:error, "error decoding bytes: " <> _} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector(),
                 client: StaticEthCallClient
               )
    end

    test "returns a selector decode error when the inner bytes do not match returns" do
      set_sleuth_result(<<1, 2, 3>>)

      assert {:error, "error decoding: " <> _} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector(),
                 client: StaticEthCallClient
               )
    end

    test "postprocesses empty and unnamed returns" do
      assert {:ok, []} = query_static(<<>>, [])

      selector = %ABI.FunctionSelector{types: [%{type: {:uint, 256}}], returns: [%{name: nil, type: {:uint, 256}}]}
      assert {:ok, [7]} = query_static(ABI.TypeEncoder.encode([7], selector), selector.returns)
    end

    test "postprocesses fixed bytes and scalar values when binary decoding is disabled" do
      selector = %ABI.FunctionSelector{
        returns: [%{name: "fixed", type: {:bytes, 3}}, %{name: "n", type: {:uint, 256}}]
      }

      query_result =
        ABI.TypeEncoder.encode([{<<1, 2, 3>>, 7}], %ABI.FunctionSelector{types: [%{type: {:tuple, selector.returns}}]})

      assert {:ok, [fixed: "0x010203", n: 7]} =
               query_static(query_result, selector.returns, decode_binaries: false, named_returns: true)
    end

    test "query/4 falls back to indexed names for multiple unnamed returns" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}, %{type: {:uint, 256}}],
        returns: [%{name: nil, type: {:uint, 256}}, %{name: nil, type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7, 8], selector))

      assert {:ok, %{"var0" => 7, "var1" => 8}} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 %ABI.FunctionSelector{returns: selector.returns},
                 client: StaticEthCallClient
               )
    end

    test "postprocesses fixed-size arrays" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:array, {:uint, 256}, 2}}],
        returns: [%{name: "items", type: {:array, {:uint, 256}, 2}}]
      }

      assert {:ok, [items: [7, 8]]} =
               query_static(ABI.TypeEncoder.encode([[7, 8]], selector), selector.returns, named_returns: true)
    end

    test "query_v2/4 preserves empty string return names when named returns are disabled" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: "", type: {:uint, 256}}]
      }

      assert {:ok, [7]} = query_static(ABI.TypeEncoder.encode([7], selector), selector.returns)
    end

    test "query/4 collapses an empty string single return to the scalar value" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: "", type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7], selector))

      assert {:ok, 7} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 %ABI.FunctionSelector{returns: selector.returns},
                 client: StaticEthCallClient
               )
    end
  end

  defp query_static(query_result, returns, opts \\ []) do
    set_sleuth_result(query_result)
    selector = %ABI.FunctionSelector{returns: returns}

    Sleuth.query_v2(
      BlockNumber.bytecode(),
      BlockNumber.encode_query(),
      selector,
      Keyword.put(opts, :client, StaticEthCallClient)
    )
  end

  defp set_sleuth_result(query_result) do
    Process.put(:sleuth_eth_call_result, Base.encode16(ABI.encode("(bytes)", [{query_result}])))
  end

  defp existing_atom?(name) do
    _atom = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end
end

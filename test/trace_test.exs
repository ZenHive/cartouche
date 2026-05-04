defmodule Cartouche.TraceTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Trace.Action

  doctest Cartouche.Trace
  doctest Action

  defp base_trace_params do
    %{
      "action" => %{
        "callType" => "call",
        "from" => "0x0000000000000000000000000000000000000000",
        "gas" => "0x0",
        "input" => "0x",
        "to" => "0x0000000000000000000000000000000000000000",
        "value" => "0x0"
      },
      "subtraces" => 0,
      "type" => "call"
    }
  end

  describe "deserialize/1 — trace_address list shapes" do
    test "mixed-element list grounds the integer | <<_::160>> union" do
      params = Map.put(base_trace_params(), "traceAddress", [42, "0x1c39ba39e4735cb65978d4db400ddd70a72dc750"])
      trace = Cartouche.Trace.deserialize(params)

      assert trace.trace_address == [42, ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]]
    end

    test "empty trace address deserializes to []" do
      params = Map.put(base_trace_params(), "traceAddress", [])
      trace = Cartouche.Trace.deserialize(params)

      assert trace.trace_address == []
    end
  end

  describe "deserialize/1 — traceAddress absent/nil (Task 55)" do
    test "missing traceAddress key raises ArgumentError" do
      params = base_trace_params()
      refute Map.has_key?(params, "traceAddress")

      assert_raise ArgumentError, ~r/missing traceAddress/, fn ->
        Cartouche.Trace.deserialize(params)
      end
    end

    test "explicit nil traceAddress raises ArgumentError" do
      params = Map.put(base_trace_params(), "traceAddress", nil)

      assert_raise ArgumentError, ~r/missing traceAddress/, fn ->
        Cartouche.Trace.deserialize(params)
      end
    end
  end

  describe "deserialize/1 — action optional field shape (Task 16/17/18)" do
    test "call action grounds present non-nil fields and zero-value boundaries" do
      trace = base_trace_params() |> Map.put("traceAddress", []) |> Cartouche.Trace.deserialize()

      assert %Action{
               call_type: "call",
               from: ~h[0x0000000000000000000000000000000000000000],
               gas: 0,
               input: "",
               to: ~h[0x0000000000000000000000000000000000000000],
               value: 0,
               init: nil,
               refund_address: nil,
               balance: nil
             } = trace.action
    end

    test "create action deserializes fields absent from create JSON to nil" do
      params =
        base_trace_params()
        |> put_in(["action"], %{
          "from" => "0x13172ee393713fba9925a9a752341ebd31e8d9a7",
          "gas" => "0x1",
          "init" => "0x",
          "value" => "0x0"
        })
        |> Map.merge(%{"traceAddress" => [0], "type" => "create"})

      trace = Cartouche.Trace.deserialize(params)

      assert %Action{
               call_type: nil,
               init: "",
               from: ~h[0x13172ee393713fba9925a9a752341ebd31e8d9a7],
               gas: 1,
               input: nil,
               to: nil,
               value: 0,
               refund_address: nil,
               balance: nil
             } = trace.action
    end

    test "suicide action deserializes call/create-only fields to nil" do
      params =
        base_trace_params()
        |> put_in(["action"], %{
          "balance" => "0x0",
          "refundAddress" => "0x0000000000b3f879cb30fe243b4dfee438691c04"
        })
        |> Map.merge(%{"traceAddress" => [1], "type" => "suicide"})

      trace = Cartouche.Trace.deserialize(params)

      assert %Action{
               call_type: nil,
               init: nil,
               from: nil,
               gas: nil,
               input: nil,
               to: nil,
               value: nil,
               refund_address: ~h[0x0000000000b3f879cb30fe243b4dfee438691c04],
               balance: 0
             } = trace.action
    end
  end

  describe "deserialize/1 — top-level optional field shape (Task 16/17/18)" do
    test "present result and transaction metadata deserialize to non-nil fields" do
      params =
        Map.merge(base_trace_params(), %{
          "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
          "blockNumber" => 3_068_185,
          "result" => %{
            "gasUsed" => "0x0",
            "output" => "0x",
            "code" => "0x",
            "address" => "0x0000000000000000000000000000000000000000"
          },
          "traceAddress" => [],
          "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
          "transactionPosition" => 0
        })

      trace = Cartouche.Trace.deserialize(params)

      assert trace.block_hash == ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add]
      assert trace.block_number == 3_068_185
      assert trace.gas_used == 0
      assert trace.output == ""
      assert trace.result_code == ""
      assert trace.result_address == ~h[0x0000000000000000000000000000000000000000]
      assert trace.transaction_hash == ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3]
      assert trace.transaction_position == 0
    end

    test "absent optional metadata and nil result deserialize to nil fields" do
      params =
        Map.merge(base_trace_params(), %{"error" => "contract address collision", "result" => nil, "traceAddress" => [0]})

      trace = Cartouche.Trace.deserialize(params)

      assert trace.block_hash == nil
      assert trace.block_number == nil
      assert trace.gas_used == nil
      assert trace.error == "contract address collision"
      assert trace.output == nil
      assert trace.result_code == nil
      assert trace.result_address == nil
      assert trace.transaction_hash == nil
      assert trace.transaction_position == nil
    end

    test "absent error deserializes to nil while zero subtraces stays integer zero" do
      trace = base_trace_params() |> Map.put("traceAddress", []) |> Cartouche.Trace.deserialize()

      assert trace.error == nil
      assert trace.subtraces == 0
    end
  end

  describe "deserialize_many/1" do
    test "returns a list of Trace structs each with list-shaped trace_address" do
      base = base_trace_params()

      input = [
        Map.put(base, "traceAddress", [0]),
        Map.put(base, "traceAddress", [1, 2])
      ]

      assert [
               %Cartouche.Trace{trace_address: [0]},
               %Cartouche.Trace{trace_address: [1, 2]}
             ] = Cartouche.Trace.deserialize_many(input)
    end
  end

  describe "serialize/1 — nil optional fields (Task 16/17/18)" do
    test "nil block_hash and transaction_hash serialize to nil" do
      trace =
        %Cartouche.Trace{
          action: %Action{call_type: "call", from: <<0::160>>, gas: 0, input: "", to: <<0::160>>, value: 0},
          block_hash: nil,
          block_number: nil,
          gas_used: nil,
          error: nil,
          output: nil,
          result_code: nil,
          result_address: nil,
          subtraces: 0,
          trace_address: [],
          transaction_hash: nil,
          transaction_position: nil,
          type: "call"
        }

      serialized = Cartouche.Trace.serialize(trace)

      assert serialized.blockHash == nil
      assert serialized.blockNumber == nil
      assert serialized.transactionHash == nil
      assert serialized.transactionPosition == nil
    end

    test "nil gas_used, output, result_code, result_address serialize to nil inside result map" do
      trace =
        %Cartouche.Trace{
          action: %Action{call_type: "call", from: <<0::160>>, gas: 0, input: "", to: <<0::160>>, value: 0},
          block_hash: nil,
          block_number: nil,
          gas_used: nil,
          error: nil,
          output: nil,
          result_code: nil,
          result_address: nil,
          subtraces: 1,
          trace_address: [0],
          transaction_hash: nil,
          transaction_position: nil,
          type: "call"
        }

      serialized = Cartouche.Trace.serialize(trace)

      assert %{gasUsed: nil, output: nil, code: nil, address: nil} = serialized.result
    end

    test "create Action with nil input, to and call_type serializes nil-mapped fields to nil" do
      # create action has init/gas/value set but input, to, call_type are nil
      action = %Action{
        call_type: nil,
        from: ~h[0x13172ee393713fba9925a9a752341ebd31e8d9a7],
        gas: 1,
        init: "",
        input: nil,
        to: nil,
        value: 0
      }

      serialized = Action.serialize(action)

      assert serialized.callType == nil
      assert serialized.input == nil
      assert serialized.to == nil
      assert serialized.init == "0x"
      assert serialized.from == "0x13172EE393713fbA9925A9A752341Ebd31e8D9a7"
    end
  end

  describe "deserialize/1 — subtraces boundary values (Task 16/17/18)" do
    test "subtraces with a large positive integer stays non_neg_integer" do
      params = base_trace_params() |> Map.merge(%{"subtraces" => 9999, "traceAddress" => [0]})
      trace = Cartouche.Trace.deserialize(params)

      assert trace.subtraces == 9999
      assert is_integer(trace.subtraces)
      assert trace.subtraces >= 0
    end

    test "subtraces with value one is preserved exactly" do
      params = base_trace_params() |> Map.merge(%{"subtraces" => 1, "traceAddress" => [0]})
      trace = Cartouche.Trace.deserialize(params)

      assert trace.subtraces == 1
    end
  end

  describe "deserialize/1 — result map partial presence (Task 16/17/18)" do
    test "result with only gasUsed and output leaves result_code and result_address nil" do
      params =
        Map.merge(base_trace_params(), %{
          "result" => %{"gasUsed" => "0x5208", "output" => "0x"},
          "traceAddress" => []
        })

      trace = Cartouche.Trace.deserialize(params)

      assert trace.gas_used == 21000
      assert trace.output == ""
      assert trace.result_code == nil
      assert trace.result_address == nil
    end

    test "result with code and address but no output leaves output nil" do
      params =
        Map.merge(base_trace_params(), %{
          "result" => %{
            "gasUsed" => "0x1",
            "code" => "0xdeadbeef",
            "address" => "0x0000000000000000000000000000000000000001"
          },
          "traceAddress" => [0]
        })

      trace = Cartouche.Trace.deserialize(params)

      assert trace.gas_used == 1
      assert trace.output == nil
      assert trace.result_code == <<0xDE, 0xAD, 0xBE, 0xEF>>
      assert trace.result_address == ~h[0x0000000000000000000000000000000000000001]
    end
  end

  describe "Action.deserialize/1 — optional nil fields regression (Task 16/17/18)" do
    test "delegatecall action type deserializes correctly" do
      action_params = %{
        "callType" => "delegatecall",
        "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
        "gas" => "0x1a1f8",
        "input" => "0x",
        "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
        "value" => "0x0"
      }

      action = Action.deserialize(action_params)

      assert action.call_type == "delegatecall"
      assert action.from == ~h[0x83806d539d4ea1c140489a06660319c9a303f874]
      assert action.gas == 0x1A1F8
      assert action.input == ""
      assert action.to == ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]
      assert action.value == 0
      assert action.init == nil
      assert action.refund_address == nil
      assert action.balance == nil
    end

    test "staticcall action type has nil init, refund_address and balance" do
      action_params = %{
        "callType" => "staticcall",
        "from" => "0x0000000000000000000000000000000000000000",
        "gas" => "0xff",
        "input" => "0xdeadbeef",
        "to" => "0x0000000000000000000000000000000000000001",
        "value" => "0x0"
      }

      action = Action.deserialize(action_params)

      assert action.call_type == "staticcall"
      assert action.init == nil
      assert action.refund_address == nil
      assert action.balance == nil
    end

    test "create action non-zero gas and value decode correctly with nil call/suicide fields" do
      action_params = %{
        "from" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
        "gas" => "0x4ad07",
        "init" => "0x6060",
        "value" => "0x64"
      }

      action = Action.deserialize(action_params)

      assert action.gas == 0x4AD07
      assert action.value == 100
      assert action.init == <<0x60, 0x60>>
      assert action.call_type == nil
      assert action.input == nil
      assert action.to == nil
    end
  end

  describe "serialize/1 — roundtrip for trace_callMany payload (Task 16/17/18)" do
    test "deserialize then serialize preserves nil block and transaction fields" do
      params =
        base_trace_params()
        |> Map.merge(%{
          "result" => %{"gasUsed" => "0x0", "output" => "0x"},
          "traceAddress" => []
        })

      trace = Cartouche.Trace.deserialize(params)
      serialized = Cartouche.Trace.serialize(trace)

      assert serialized.blockHash == nil
      assert serialized.blockNumber == nil
      assert serialized.transactionHash == nil
      assert serialized.transactionPosition == nil
      assert serialized.type == "call"
      assert serialized.subtraces == 0
    end
  end
end

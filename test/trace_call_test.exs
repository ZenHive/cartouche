defmodule Cartouche.TraceCallTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  doctest Cartouche.TraceCall

  defp single_trace_map do
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
      "type" => "call",
      "traceAddress" => [0]
    }
  end

  describe "deserialize/1 — trace list shape" do
    test "empty trace list deserializes to []" do
      input = %{"output" => "0x", "trace" => []}

      assert %Cartouche.TraceCall{output: "", trace: []} = Cartouche.TraceCall.deserialize(input)
    end
  end

  describe "deserialize/1 — wrapper fields shape (Task 16/17/18)" do
    test "output decodes non-empty hex and unsupported traces stay nil" do
      input = %{
        "output" => "0x01020304",
        "stateDiff" => %{"ignored" => true},
        "trace" => [],
        "vmTrace" => %{"ignored" => true}
      }

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert trace_call.output == ~h[0x01020304]
      assert trace_call.state_diff == nil
      assert trace_call.vm_trace == nil
    end

    test "empty output hex decodes to an empty binary" do
      input = %{"output" => "0x", "trace" => []}

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert trace_call.output == ""
    end

    test "embedded Trace structs retain nil fields from trace_callMany payloads" do
      input = %{"output" => "0x", "trace" => [single_trace_map()]}

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert [
               %Cartouche.Trace{
                 block_hash: nil,
                 block_number: nil,
                 transaction_hash: nil,
                 transaction_position: nil
               }
             ] = trace_call.trace
    end
  end

  describe "deserialize_many/1" do
    test "returns a list of TraceCall structs each with list-shaped trace" do
      input = [
        %{"output" => "0x", "trace" => [single_trace_map()]},
        %{"output" => "0x", "trace" => [single_trace_map(), single_trace_map()]}
      ]

      assert [
               %Cartouche.TraceCall{trace: [%Cartouche.Trace{trace_address: [0]}]},
               %Cartouche.TraceCall{
                 trace: [
                   %Cartouche.Trace{trace_address: [0]},
                   %Cartouche.Trace{trace_address: [0]}
                 ]
               }
             ] = Cartouche.TraceCall.deserialize_many(input)
    end
  end

  describe "serialize/1 — nil optional fields in embedded traces (Task 16/17/18)" do
    test "serialize encodes output binary back to hex string" do
      trace_call = %Cartouche.TraceCall{
        output: "",
        state_diff: nil,
        trace: [],
        vm_trace: nil
      }

      serialized = Cartouche.TraceCall.serialize(trace_call)

      assert serialized.output == "0x"
    end

    test "serialize encodes non-empty output binary back to hex string" do
      trace_call = %Cartouche.TraceCall{
        output: ~h[0x01020304],
        state_diff: nil,
        trace: [],
        vm_trace: nil
      }

      serialized = Cartouche.TraceCall.serialize(trace_call)

      assert serialized.output == "0x01020304"
    end

    test "serialize propagates nil block_hash and transaction_hash from embedded traces" do
      input = %{"output" => "0x", "trace" => [single_trace_map()]}
      trace_call = Cartouche.TraceCall.deserialize(input)
      serialized = Cartouche.TraceCall.serialize(trace_call)

      assert [serialized_trace] = serialized.trace
      assert serialized_trace.blockHash == nil
      assert serialized_trace.blockNumber == nil
      assert serialized_trace.transactionHash == nil
      assert serialized_trace.transactionPosition == nil
    end

    test "serialize sets stateDiff and vmTrace to nil" do
      trace_call = %Cartouche.TraceCall{
        output: "",
        state_diff: nil,
        trace: [],
        vm_trace: nil
      }

      serialized = Cartouche.TraceCall.serialize(trace_call)

      assert serialized.stateDiff == nil
      assert serialized.vmTrace == nil
    end
  end

  describe "deserialize/1 — missing optional keys (Task 16/17/18)" do
    test "deserialize without stateDiff or vmTrace keys sets those fields to nil" do
      input = %{"output" => "0x", "trace" => []}

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert trace_call.state_diff == nil
      assert trace_call.vm_trace == nil
    end

    test "deserialize with create-type trace retains nil input and nil to in embedded action" do
      create_trace_map = %{
        "action" => %{
          "from" => "0x13172ee393713fba9925a9a752341ebd31e8d9a7",
          "gas" => "0x1",
          "init" => "0x",
          "value" => "0x0"
        },
        "subtraces" => 0,
        "type" => "create",
        "traceAddress" => [0]
      }

      input = %{"output" => "0x", "trace" => [create_trace_map]}
      trace_call = Cartouche.TraceCall.deserialize(input)

      assert [%Cartouche.Trace{action: action}] = trace_call.trace
      assert action.input == nil
      assert action.to == nil
      assert action.call_type == nil
      assert action.init == ""
    end

    test "deserialize with suicide-type trace retains nil from/gas/input/value in embedded action" do
      suicide_trace_map = %{
        "action" => %{
          "balance" => "0x0",
          "refundAddress" => "0x0000000000b3f879cb30fe243b4dfee438691c04"
        },
        "subtraces" => 0,
        "type" => "suicide",
        "traceAddress" => [1]
      }

      input = %{"output" => "0x", "trace" => [suicide_trace_map]}
      trace_call = Cartouche.TraceCall.deserialize(input)

      assert [%Cartouche.Trace{action: action}] = trace_call.trace
      assert action.from == nil
      assert action.gas == nil
      assert action.input == nil
      assert action.value == nil
      assert action.balance == 0
    end
  end

  describe "deserialize_many/1 — nil field propagation (Task 16/17/18)" do
    test "all TraceCall structs in a many-result have nil block and transaction fields on traces" do
      input = [
        %{"output" => "0x", "trace" => [single_trace_map()]},
        %{"output" => "0x", "trace" => [single_trace_map()]}
      ]

      [first, second] = Cartouche.TraceCall.deserialize_many(input)

      for trace_call <- [first, second] do
        [trace] = trace_call.trace
        assert trace.block_hash == nil
        assert trace.transaction_hash == nil
      end
    end
  end
end

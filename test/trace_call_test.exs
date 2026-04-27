defmodule Cartouche.TraceCallTest do
  use ExUnit.Case, async: true

  doctest Cartouche.TraceCall

  describe "deserialize/1 — trace list shape" do
    test "empty trace list deserializes to []" do
      input = %{"output" => "0x", "trace" => []}

      assert %Cartouche.TraceCall{output: "", trace: []} = Cartouche.TraceCall.deserialize(input)
    end
  end

  describe "deserialize_many/1" do
    test "returns a list of TraceCall structs each with list-shaped trace" do
      single_trace_map = %{
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

      input = [
        %{"output" => "0x", "trace" => [single_trace_map]},
        %{"output" => "0x", "trace" => [single_trace_map, single_trace_map]}
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
end

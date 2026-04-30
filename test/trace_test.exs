defmodule Cartouche.TraceTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  doctest Cartouche.Trace
  doctest Cartouche.Trace.Action

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
end

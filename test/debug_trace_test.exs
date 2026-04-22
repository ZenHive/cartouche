defmodule Cartouche.DebugTraceTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex
  doctest Cartouche.DebugTrace
  doctest Cartouche.DebugTrace.StructLog
end

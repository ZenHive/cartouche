defmodule Cartouche.TypedTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex
  doctest Cartouche.Typed
  doctest Cartouche.Typed.Domain
  doctest Cartouche.Typed.Type
end

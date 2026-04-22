defmodule CartoucheTest do
  use ExUnit.Case, async: true

  doctest Cartouche

  test "version/0 returns the mix.exs version" do
    assert Cartouche.version() == "0.0.1"
  end
end

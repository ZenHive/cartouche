defmodule Cartouche.WeiTest do
  use ExUnit.Case, async: true

  alias Cartouche.Wei

  doctest Wei

  describe "spec boundaries (Phase 1.2)" do
    test "zero is the lower boundary in all three clauses" do
      assert Wei.to_wei(0) == 0
      assert Wei.to_wei({0, :wei}) == 0
      assert Wei.to_wei({0, :gwei}) == 0
    end

    test "large non-negative integer round-trips through identity clauses" do
      large = 0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF
      assert Wei.to_wei(large) == large
      assert Wei.to_wei({large, :wei}) == large
    end

    test ":gwei multiplier applies as documented" do
      assert Wei.to_wei({1, :gwei}) == 1_000_000_000
      assert Wei.to_wei({2, :gwei}) == 2_000_000_000
    end

    test "negative inputs are out of contract and raise FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Wei.to_wei(-1) end
      assert_raise FunctionClauseError, fn -> Wei.to_wei({-1, :wei}) end
      assert_raise FunctionClauseError, fn -> Wei.to_wei({-1, :gwei}) end
    end
  end
end

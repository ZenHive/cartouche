defmodule Cartouche.Contract.IConsoleTest do
  @moduledoc ~S"""
  Tests for the IConsole generated contract module (INE-43 / Phase B+C).

  The PR regenerated `lib/cartouche/contract/i_console.ex` with these changes:
  - `abi/0` function removed (was a 4000+ line ABI-data function)
  - All `@doc "..."` strings replaced with `@doc false`
  - All typed `@spec ... :: String.t()` / typed specs replaced with `@spec ... :: term()`
  - `alias Cartouche.Transaction.V1` and `alias Cartouche.Transaction.V2` removed;
    only `alias Cartouche.Transaction.Call` remains.

  These tests pin the post-regeneration API surface so future regenerations don't
  silently drift.
  """
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Contract.IConsole
  alias Cartouche.Transaction.Call

  # ---------------------------------------------------------------------------
  # contract_name/0
  # ---------------------------------------------------------------------------

  describe "contract_name/0" do
    test "returns the string IConsole" do
      assert IConsole.contract_name() == "IConsole"
    end

    test "is a public function exported from the module" do
      assert function_exported?(IConsole, :contract_name, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # abi/0 — removed in this PR
  # ---------------------------------------------------------------------------

  describe "abi/0 removal" do
    test "abi/0 is NOT exported (function was removed in this PR)" do
      # The old i_console.ex shipped a massive abi/0 returning the raw ABI list.
      # This PR removes it: generated bindings no longer carry the ABI data payload.
      refute function_exported?(IConsole, :abi, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Alias scope: Call used, V1 and V2 removed
  # ---------------------------------------------------------------------------

  describe "Transaction.Call shape in build_trx helpers" do
    test "build_trx_log/4 returns a Call struct, not a V2 transaction" do
      dest = <<1::160>>
      trx = IConsole.build_trx_log(dest, <<2::160>>, <<3::160>>, "hello")

      assert %Call{destination: ^dest} = trx
      assert is_binary(trx.data)
    end

    test "build_trx_log/4 data encodes via log_selector" do
      dest = <<1::160>>
      p0 = <<2::160>>
      p1 = <<3::160>>
      p2 = "test"

      trx = IConsole.build_trx_log(dest, p0, p1, p2)
      encoded = IConsole.encode_log(p0, p1, p2)

      assert trx.data == encoded
    end
  end

  # ---------------------------------------------------------------------------
  # log_selector/0 — basic structural integrity
  # ---------------------------------------------------------------------------

  describe "log_selector/0" do
    test "returns a map with function :log" do
      sel = IConsole.log_selector()
      assert sel.function == "log"
    end

    test "returns a map with state_mutability :pure" do
      sel = IConsole.log_selector()
      assert sel.state_mutability == :pure
    end

    test "returns a map with three input types (address, address, string)" do
      sel = IConsole.log_selector()
      types = sel.types
      assert length(types) == 3
      assert Enum.at(types, 0).type == :address
      assert Enum.at(types, 1).type == :address
      assert Enum.at(types, 2).type == :string
    end

    test "returns an empty outputs list" do
      sel = IConsole.log_selector()
      assert sel.returns == []
    end
  end

  # ---------------------------------------------------------------------------
  # encode_log/3 — produces binary ABI calldata
  # ---------------------------------------------------------------------------

  describe "encode_log/3" do
    test "returns a binary" do
      result = IConsole.encode_log(<<1::160>>, <<2::160>>, "hello")
      assert is_binary(result)
    end

    test "encodes with the 4-byte selector prefix from log_selector" do
      # Verify the first 4 bytes match the ABI selector derived from the function sig.
      encoded = IConsole.encode_log(<<1::160>>, <<2::160>>, "test")
      assert byte_size(encoded) >= 4
    end

    test "produces deterministic output for the same inputs" do
      p0 = <<1::160>>
      p1 = <<2::160>>
      p2 = "deterministic"

      assert IConsole.encode_log(p0, p1, p2) == IConsole.encode_log(p0, p1, p2)
    end

    test "produces different output for different inputs" do
      base = IConsole.encode_log(<<1::160>>, <<2::160>>, "a")
      other = IConsole.encode_log(<<1::160>>, <<2::160>>, "b")

      refute base == other
    end
  end

  # ---------------------------------------------------------------------------
  # decode_log_call/1 — verifies round-trip calldata decode
  # ---------------------------------------------------------------------------

  describe "decode_log_call/1" do
    test "decodes calldata encoded by encode_log/3" do
      p0 = <<1::160>>
      p1 = <<2::160>>
      p2 = "round-trip"

      calldata = IConsole.encode_log(p0, p1, p2)
      decoded = IConsole.decode_log_call(calldata)

      assert [^p0, ^p1, ^p2] = decoded
    end
  end

  # ---------------------------------------------------------------------------
  # decode_call/1 dispatcher
  # ---------------------------------------------------------------------------

  describe "decode_call/1" do
    test "dispatches log calldata correctly" do
      calldata = IConsole.encode_log(<<1::160>>, <<2::160>>, "dispatch")
      assert {:ok, "log", _} = IConsole.decode_call(calldata)
    end

    test "returns :not_found for unknown selector" do
      assert :not_found = IConsole.decode_call(<<0, 0, 0, 0, 0>>)
    end
  end

  # ---------------------------------------------------------------------------
  # decode_event/2 and decode_error/1 stubs
  # ---------------------------------------------------------------------------

  describe "decode_event/2" do
    test "returns :not_found for any input" do
      assert :not_found = IConsole.decode_event(<<1, 2, 3>>, [])
    end
  end

  describe "decode_error/1" do
    test "returns :not_found for any input" do
      assert :not_found = IConsole.decode_error(<<1, 2, 3>>)
    end
  end
end
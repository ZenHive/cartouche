defmodule Cartouche.RecoveryBitTest do
  use ExUnit.Case, async: false

  doctest Cartouche.RecoveryBit

  describe "EIP-155 normalization" do
    setup do
      previous_chain_id = Application.get_env(:cartouche, :chain_id)
      Application.put_env(:cartouche, :chain_id, 5)

      on_exit(fn ->
        if is_nil(previous_chain_id) do
          Application.delete_env(:cartouche, :chain_id)
        else
          Application.put_env(:cartouche, :chain_id, previous_chain_id)
        end
      end)
    end

    test "normalize/2 applies the configured chain id" do
      assert Cartouche.RecoveryBit.normalize(28, :eip155) == 46
    end

    test "normalize_signature/2 applies the configured chain id" do
      assert Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 28>>, :eip155) ==
               <<1::256, 2::256, 46>>
    end

    test "recover_base/1 returns 0/1 for valid EIP-155 recovery bits" do
      assert Cartouche.RecoveryBit.recover_base(45) == 0
      assert Cartouche.RecoveryBit.recover_base(46) == 1
    end

    test "recover_base/1 reports the configured chain id for invalid EIP-155 values" do
      assert_raise RuntimeError, "Invalid EIP-155 Signature: recovery_bit=47, chain_id=5", fn ->
        Cartouche.RecoveryBit.recover_base(47)
      end
    end
  end
end

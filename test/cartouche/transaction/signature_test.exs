defmodule Cartouche.Transaction.SignatureTest do
  use ExUnit.Case, async: true

  alias Cartouche.Transaction.Signature
  alias Cartouche.Transaction.V3

  describe "y_parity_from_v/1" do
    test "treats 0 and 1 as direct y-parity values" do
      assert Signature.y_parity_from_v(<<0>>) == false
      assert Signature.y_parity_from_v(<<1>>) == true
    end

    test "derives y-parity from EIP-155-style recovery bits" do
      assert Signature.y_parity_from_v(<<38::8>>) == true
      assert Signature.y_parity_from_v(<<27::8>>) == false
    end
  end

  describe "add_packed/2" do
    test "attaches packed signature fields to a transaction struct" do
      tx = %V3{signature_y_parity: nil, signature_r: nil, signature_s: nil}

      assert %V3{signature_y_parity: true, signature_r: <<1::256>>, signature_s: <<2::256>>} =
               Signature.add_packed(tx, <<1::256, 2::256, 1>>)
    end

    test "rejects packed signatures without a recovery byte" do
      tx = %V3{signature_y_parity: nil, signature_r: nil, signature_s: nil}

      assert_raise FunctionClauseError, fn ->
        Signature.add_packed(tx, <<1::256, 2::256>>)
      end
    end
  end
end

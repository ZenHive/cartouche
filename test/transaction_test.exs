defmodule Cartouche.TransactionTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Test.Signer
  alias Cartouche.Transaction
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  doctest Transaction
  doctest V1
  doctest V2

  describe "V2.new/9 (no signature)" do
    test "chain_id: nil falls back to Application.chain_id()" do
      trx = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<>>, [])
      # TODO(Task 39): hardcoded `5` couples this test to `config/test.exs` setting :goerli.
      # Sweep alongside the RecoveryBit doctest portability cleanup tracked by Task 39.
      assert trx.chain_id == 5
      assert trx.signature_y_parity == nil
      assert trx.signature_r == nil
      assert trx.signature_s == nil
    end

    test "explicit chain_id is parsed" do
      trx = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<>>, [], :mainnet)
      assert trx.chain_id == 1
    end
  end

  describe "V2.new/12 (signed)" do
    test "max_priority_fee_per_gas: nil and max_fee_per_gas: nil pass through as nil" do
      trx =
        V2.new(
          1,
          nil,
          nil,
          100_000,
          <<1::160>>,
          {2, :wei},
          <<>>,
          [],
          true,
          <<1::256>>,
          <<2::256>>,
          :goerli
        )

      assert trx.max_priority_fee_per_gas == nil
      assert trx.max_fee_per_gas == nil
      assert trx.signature_y_parity == true
    end
  end

  describe "build_trx_v2/9" do
    test "ABI-tuple call_data is encoded" do
      trx =
        Transaction.build_trx_v2(
          <<1::160>>,
          5,
          {"baz(uint256,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          [],
          :goerli
        )

      assert is_binary(trx.data)
      # 4-byte selector + two 32-byte words = 68 bytes
      assert byte_size(trx.data) == 68
    end

    test "raw binary call_data is preserved verbatim" do
      data = <<0x12, 0x34>>

      trx =
        Transaction.build_trx_v2(
          <<1::160>>,
          5,
          data,
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          [],
          :goerli
        )

      assert trx.data == data
    end
  end

  describe "build_signed_trx_v2/9" do
    test "happy path: signature recovers to signer's address" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        Transaction.build_signed_trx_v2(
          <<1::160>>,
          5,
          <<>>,
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          [],
          signer: signer_proc,
          chain_id: :goerli
        )

      assert signed.signature_y_parity in [true, false]
      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      {:ok, recovered} = V2.recover_signer(signed)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "callback returning {:error, _} short-circuits the with-pipeline" do
      signer_proc = Signer.start_signer()

      assert {:error, :nope} =
               Transaction.build_signed_trx_v2(
                 <<1::160>>,
                 5,
                 <<>>,
                 {1, :gwei},
                 {100, :gwei},
                 100_000,
                 0,
                 [],
                 signer: signer_proc,
                 chain_id: :goerli,
                 callback: fn _trx -> {:error, :nope} end
               )
    end
  end

  describe "V2.decode/1" do
    test "malformed RLP body returns {:error, \"invalid v2 transaction\"}" do
      bad_body = <<0x02>> <> ExRLP.encode([<<1>>, <<2>>, <<3>>])
      assert {:error, "invalid v2 transaction"} = V2.decode(bad_body)
    end
  end

  describe "V1 (Task 53 — r/s/v unification + decode→recover_signer round-trip)" do
    test "decode/1 returns {:error, \"invalid legacy transaction\"} on malformed RLP" do
      bad_body = ExRLP.encode([<<1>>, <<2>>, <<3>>])
      assert {:error, "invalid legacy transaction"} = V1.decode(bad_body)
    end

    test "decode → recover_signer round-trip recovers the original signer" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        Transaction.build_signed_trx(<<1::160>>, 5, <<>>, {50, :gwei}, 100_000, 0,
          signer: signer_proc,
          chain_id: :goerli
        )

      {:ok, decoded} = V1.decode(V1.encode(signed))
      {:ok, recovered} = V1.recover_signer(decoded, 5)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "decode of unsigned RLP yields r=0, s=0; recover_signer reports missing signature" do
      encoded = V1.encode(V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan))
      {:ok, decoded} = V1.decode(encoded)
      assert decoded.r == 0
      assert decoded.s == 0
      assert {:error, "transaction missing signature"} = V1.recover_signer(decoded, :kovan)
    end

    test "decode/1 rejects RLP with r or s wider than 32 bytes" do
      adversarial =
        ExRLP.encode([
          <<1>>,
          <<100_000_000_000::40>>,
          <<100_000::24>>,
          <<1::160>>,
          <<2>>,
          <<1, 2, 3>>,
          <<42>>,
          <<1, 0::256>>,
          <<2::256>>
        ])

      assert {:error, "invalid legacy transaction"} = V1.decode(adversarial)
    end
  end
end

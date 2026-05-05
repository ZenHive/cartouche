defmodule Cartouche.TransactionTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Signer.Default
  alias Cartouche.Test.Signer
  alias Cartouche.Transaction
  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V4

  doctest Call
  doctest Transaction
  doctest V1
  doctest V2
  doctest V4

  describe "Call.new/3" do
    test "builds eth_call params without transaction-only fields" do
      call = Call.new(<<1::160>>, <<0x12, 0x34>>, from: <<2::160>>, gas: 21_000, value: 7)

      assert %Call{
               destination: <<1::160>>,
               data: <<0x12, 0x34>>,
               from: <<2::160>>,
               gas: 21_000,
               value: 7
             } = call

      refute Map.has_key?(call, :nonce)
      refute Map.has_key?(call, :chain_id)
      refute Map.has_key?(call, :signature_r)
    end
  end

  describe "V2.new/9 (no signature)" do
    test "chain_id: nil falls back to Application.chain_id()" do
      trx = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<>>, [])
      assert trx.chain_id == Cartouche.Application.chain_id()
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
    test "default chain_id falls back to Application.chain_id()" do
      trx =
        Transaction.build_trx_v2(
          <<1::160>>,
          5,
          <<0x12, 0x34>>,
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          []
        )

      assert trx.chain_id == Cartouche.Application.chain_id()
      assert trx.data == <<0x12, 0x34>>
    end

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

  describe "build_trx/7" do
    test "raw binary call_data is preserved with default chain_id" do
      trx = Transaction.build_trx(<<1::160>>, 5, <<0x12, 0x34>>, {50, :gwei}, 100_000, 0)

      assert trx.v == Cartouche.Application.chain_id()
      assert trx.data == <<0x12, 0x34>>
    end

    test "ABI-tuple call_data is encoded" do
      trx =
        Transaction.build_trx(
          <<1::160>>,
          5,
          {"baz(uint256,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
          {50, :gwei},
          100_000,
          0,
          :goerli
        )

      assert trx.v == 5
      assert byte_size(trx.data) == 68
    end
  end

  describe "build_signed_trx/7" do
    test "default signer path surfaces the current nil chain-id boundary" do
      Signer.start_signer(Default)

      assert catch_exit(Transaction.build_signed_trx(<<1::160>>, 5, <<>>, {50, :gwei}, 100_000, 0))
    end

    test "callback can transform the unsigned transaction before signing" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        Transaction.build_signed_trx(<<1::160>>, 5, <<0x12>>, {50, :gwei}, 100_000, 0,
          signer: signer_proc,
          chain_id: :goerli,
          callback: fn trx -> {:ok, %{trx | data: <<0x34>>}} end
        )

      assert signed.data == <<0x34>>
      {:ok, recovered} = V1.recover_signer(signed, :goerli)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end
  end

  describe "build_signed_trx_v2/9" do
    test "default signer path surfaces the current nil chain-id boundary" do
      Signer.start_signer(Default)

      assert catch_exit(Transaction.build_signed_trx_v2(<<1::160>>, 5, <<>>, {1, :gwei}, {100, :gwei}, 100_000, 0, []))
    end

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

  describe "V4 encode/decode" do
    test "new/10 defaults chain id and preserves nil fee fields before encoding" do
      transaction =
        V4.new(
          1,
          nil,
          nil,
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          nil,
          [signed_authorization(1, <<2::160>>, 7)]
        )

      assert transaction.chain_id == Cartouche.Application.chain_id()
      assert transaction.max_priority_fee_per_gas == nil
      assert transaction.max_fee_per_gas == nil
    end

    test "round-trips a representative authorization-list transaction" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "round-trips unsigned transactions without signature fields" do
      transaction = V4.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], [], :mainnet)

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "round-trips access-list storage keys" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> Map.put(:access_list, [{<<3::160>>, [<<4::256>>]}])

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "supports empty authorization lists at the RLP boundary" do
      transaction = v4_transaction([])

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "normalizes nil authorization lists at the encoding boundary" do
      transaction =
        1
        |> V4.new({1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], nil, :mainnet)
        |> V4.add_signature(<<1::256, 2::256, 1>>)

      assert {:ok, %{authorization_list: []}} = transaction |> V4.encode() |> V4.decode()
    end

    test "supports multiple authorization entries including chain_id 0" do
      authorizations = [
        signed_authorization(1, <<2::160>>, 7),
        signed_authorization(0, <<3::160>>, 8)
      ]

      transaction = v4_transaction(authorizations)

      assert {:ok, %{authorization_list: ^authorizations}} = transaction |> V4.encode() |> V4.decode()
    end

    test "decode rejects malformed typed payloads" do
      bad_body = <<0x04>> <> ExRLP.encode([<<1>>, <<2>>, <<3>>])
      assert {:error, "invalid v4 transaction"} = V4.decode(bad_body)
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x02, 0xC0>>)
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x04, 0xFF>>)
    end

    test "decode rejects malformed authorization entries" do
      malformed_authorization = [<<1>>, <<2::160>>, <<7>>, <<0>>, <<1, 0::256>>, <<2::256>>]

      encoded =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            [malformed_authorization],
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(encoded)
    end

    test "decode rejects malformed access-list entries" do
      encoded =
        1
        |> signed_authorization(<<2::160>>, 7)
        |> List.wrap()
        |> v4_transaction()
        |> V4.encode()

      <<0x04, encoded_payload::binary>> = encoded

      [
        chain_id,
        nonce,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        destination,
        amount,
        data,
        _access_list,
        authorization_list,
        y_parity,
        r,
        s
      ] = ExRLP.decode(encoded_payload)

      malformed_access_list = [[<<1, 2>>, [<<1::256>>]]]

      bad_body =
        <<0x04>> <>
          ExRLP.encode([
            chain_id,
            nonce,
            max_priority_fee_per_gas,
            max_fee_per_gas,
            gas_limit,
            destination,
            amount,
            data,
            malformed_access_list,
            authorization_list,
            y_parity,
            r,
            s
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(bad_body)
    end

    test "decode rejects malformed access-list and authorization-list containers" do
      bad_access_list =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            <<>>,
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      bad_authorization_list =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            <<>>,
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(bad_access_list)
      assert {:error, "invalid v4 transaction"} = V4.decode(bad_authorization_list)
    end

    test "decode rejects malformed storage-key lists, y-parity values, and entry shapes" do
      malformed_storage =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [[<<2::160>>, [<<1, 2>>]]],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      malformed_y_parity =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            2,
            1,
            2
          ])

      malformed_access_entry =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [[<<2::160>>]],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      malformed_authorization_entry =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            [[<<1>>, <<2::160>>]],
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_storage)
      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_y_parity)
      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_access_entry)
      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_authorization_entry)
    end

    test "decode rejects non-binary data payloads" do
      encoded =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            [<<1, 2, 3>>],
            [],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(encoded)
    end
  end

  describe "V4 signatures and hashes" do
    test "default signer path signs with the configured signer chain id" do
      Signer.start_signer(Default)
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert {:ok, %V4{signature_r: <<_::256>>, signature_s: <<_::256>>}} = V4.sign(transaction)

      assert {:ok, {1, <<2::160>>, 7, _y_parity, <<_::256>>, <<_::256>>}} =
               V4.sign_authorization({1, <<2::160>>, 7})
    end

    test "sign/2 signs the outer transaction and recovers the signer" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> V4.sign(signer_proc)

      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      {:ok, recovered} = V4.recover_signer(signed)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "hash/1 returns the keccak of encoded bytes" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> V4.add_signature(<<1::256, 2::256, 1>>)

      assert V4.hash(transaction) == transaction |> V4.encode() |> Cartouche.Hash.keccak()
      assert V4.hash(V4.encode(transaction)) == V4.hash(transaction)
    end

    test "encodes signatures with binary-safe leading-zero trimming" do
      transaction =
        []
        |> v4_transaction()
        |> Map.merge(%{signature_r: <<0, 0xFF, 1::240>>, signature_s: <<0, 0xFE, 2::240>>})

      <<0x04, payload::binary>> = V4.encode(transaction)
      decoded_fields = ExRLP.decode(payload)

      assert [<<0xFF, 1::240>>, <<0xFE, 2::240>>] = Enum.slice(decoded_fields, 11, 2)
    end

    test "authorization_hash/1 accepts signed and unsigned authorization tuples" do
      unsigned = {1, <<2::160>>, 7}
      signed = signed_authorization(1, <<2::160>>, 7)

      assert V4.authorization_hash(unsigned) == V4.authorization_hash(signed)
    end

    test "sign_authorization/2 signs an authorization tuple and recovers authority" do
      signer_proc = Signer.start_signer()

      {:ok, authorization} = V4.sign_authorization({0, <<2::160>>, 7}, signer_proc)
      assert {0, <<2::160>>, 7, _y_parity, <<_::256>>, <<_::256>>} = authorization

      {:ok, recovered} = V4.recover_authority(authorization)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "missing signatures return explicit errors" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])
      authorization = {1, <<2::160>>, 7, nil, nil, nil}

      assert {:error, "transaction missing signature"} =
               transaction
               |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
               |> V4.get_signature()

      assert {:error, "transaction missing signature"} =
               transaction
               |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
               |> V4.recover_signer()

      assert {:error, "authorization missing signature"} = V4.get_authorization_signature(authorization)
      assert {:error, "authorization missing signature"} = V4.recover_authority(authorization)
    end

    test "rejects packed signatures without recovery bytes" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])
      authorization = {1, <<2::160>>, 7, nil, nil, nil}

      assert_raise FunctionClauseError, fn -> V4.add_signature(transaction, <<1::256, 2::256>>) end

      assert_raise FunctionClauseError, fn ->
        V4.add_authorization_signature(authorization, <<1::256, 2::256>>)
      end
    end
  end

  describe "V4 mainnet vector" do
    test "decodes a real mainnet EIP-7702 transaction and validates signatures" do
      raw =
        ~h[0x04f90235018208f685012a05f20085013351f4d0830490c594f827725498e6fcf62d331566965f5254bcda081f80b9016408c1284c00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000104039a40f2bccd543a5eaaaca3a5749d912087ef66220000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000106545ff956995f0000b25750fa55b302c9a3997f64d24c0b14afdd316500006401da7d6fa850c02ec58ac50ae3c7137b47cb8ae7990007d00003001101033d007224df0a5cf63f33a4e5f25b392097f16bfc0006545ff956995f0208f60469f93ef30141d79dad548078b26c02aaf2a3ae4c2e723245701f0f71f77349bddf24e0aed1c9096d5005a0b468cd4ac1a34793d4fa10a2ac04af8685b6f3e82298a9e5ae44771b010200023d007224df0a5cf63f33a4e5f25b392097f16bfc0026f20202010200000000000000000000000000000000000000000000000000000000c0f85ef85c019400000000000000000000000000000000000000008208f780a007359171ab176f57c49420481d6a4ba45593d0bd4c16e6273ff88684e7821c9ca05b2fc15416887a236607e4f277e053db645cae48bf810b43c654f2cff6ab575c01a0e8375ec8c35be742c2e2b637ddc4a5c83fe3e2fa345b38debef51d38c1e50530a02e695872ee3a3a6a3ad0b44d185b98beeae8bfbb9864f9e2db5406e195b4e4c6]

      assert {:ok, transaction} = V4.decode(raw)

      assert transaction.chain_id == 1
      assert transaction.nonce == 2294
      assert transaction.max_priority_fee_per_gas == 5_000_000_000
      assert transaction.max_fee_per_gas == 5_155_976_400
      assert transaction.gas_limit == 299_205
      assert transaction.destination == ~h[0xf827725498e6fcf62d331566965f5254bcda081f]
      assert transaction.amount == 0
      assert transaction.access_list == []
      assert transaction.signature_y_parity == true

      assert [
               {
                 1,
                 ~h[0x0000000000000000000000000000000000000000],
                 2295,
                 false,
                 ~h[0x07359171ab176f57c49420481d6a4ba45593d0bd4c16e6273ff88684e7821c9c],
                 ~h[0x5b2fc15416887a236607e4f277e053db645cae48bf810b43c654f2cff6ab575c]
               } = authorization
             ] = transaction.authorization_list

      assert V4.encode(transaction) == raw
      assert V4.hash(transaction) == ~h[0xb418e774d8492b01ebc5966b2a80d873d4651351b4813e954fdbdda713081ab8]

      assert {:ok, outer_signer} = V4.recover_signer(transaction)
      assert Cartouche.Hex.to_address(outer_signer) == "0x52ceD5DD182f7CD50B8eC4A2ad0c50824DA39A66"

      assert {:ok, authority} = V4.recover_authority(authorization)
      assert Cartouche.Hex.to_address(authority) == "0x52ceD5DD182f7CD50B8eC4A2ad0c50824DA39A66"
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

  defp v4_transaction(authorization_list) do
    1
    |> V4.new(
      {1, :gwei},
      {100, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [],
      authorization_list,
      :mainnet
    )
    |> V4.add_signature(<<1::256, 2::256, 1>>)
  end

  defp signed_authorization(chain_id, address, nonce) do
    {chain_id, address, nonce, false, <<1::256>>, <<2::256>>}
  end

  defp encode_authorization_for_test({chain_id, address, nonce, y_parity, r, s}) do
    [chain_id, address, nonce, if(y_parity, do: 1, else: 0), r, s]
  end
end

defmodule Cartouche.Transaction.VectorTest do
  use ExUnit.Case, async: true

  alias Cartouche.Hash
  alias Cartouche.Hex
  alias Cartouche.Transaction
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  @fixture_paths Path.wildcard(Path.expand("../../fixtures/vectors/*.json", __DIR__))

  setup_all do
    fixtures = Enum.map(@fixture_paths, &(&1 |> File.read!() |> Jason.decode!()))
    %{fixtures: fixtures}
  end

  test "ethers and viem independently agree on every vector", %{fixtures: fixtures} do
    assert [ethers, viem] = Enum.sort_by(fixtures, &get_in(&1, ["provenance", "source_implementation"]))
    assert ethers["vectors"] == viem["vectors"]
    assert ethers["authorization"] == viem["authorization"]
  end

  test "external signed and unsigned vectors match Cartouche", %{fixtures: fixtures} do
    for fixture <- fixtures, {name, vector} <- fixture["vectors"] do
      signed = Hex.decode_hex!(vector["serialized"])
      unsigned = Hex.decode_hex!(vector["unsigned_serialized"])
      expected_signer = Hex.decode_address!(vector["from"])

      assert Hex.encode_hex(Hash.keccak(signed)) == vector["hash"]
      assert Hex.encode_hex(Hash.keccak(unsigned)) == vector["unsigned_hash"]
      assert {:ok, transaction} = Transaction.decode(signed)
      assert Transaction.encode(transaction) == signed
      assert {:ok, ^expected_signer} = recover_signer(name, transaction)
      assert {:ok, unsigned_transaction} = Transaction.decode(unsigned)
      assert Transaction.encode(unsigned_transaction) == unsigned
      assert canonical_fields(unsigned_transaction) == vector["fields"]

      assert_authority(name, transaction, fixture)
    end
  end

  defp recover_signer("v1", transaction), do: V1.recover_signer(transaction, 1)

  defp recover_signer(_name, transaction) do
    module = transaction.__struct__
    module.recover_signer(transaction)
  end

  defp assert_authority("v4", %V4{authorization_list: [authorization]}, fixture) do
    expected_authority = Hex.decode_address!(fixture["authority"])
    assert {:ok, ^expected_authority} = V4.recover_authority(authorization)
  end

  defp assert_authority(_name, _transaction, _fixture), do: :ok

  defp canonical_fields(%V1{} = transaction) do
    %{
      "chain_id" => decimal(transaction.v),
      "nonce" => decimal(transaction.nonce),
      "gas_price" => decimal(transaction.gas_price),
      "gas_limit" => decimal(transaction.gas_limit),
      "destination" => Hex.encode_hex(transaction.to),
      "amount" => decimal(transaction.value),
      "data" => Hex.encode_hex(transaction.data)
    }
  end

  defp canonical_fields(%V_2930{} = transaction) do
    transaction
    |> typed_fields()
    |> Map.put("gas_price", decimal(transaction.gas_price))
  end

  defp canonical_fields(%V2{} = transaction), do: dynamic_fee_fields(transaction)

  defp canonical_fields(%V3{} = transaction) do
    transaction
    |> dynamic_fee_fields()
    |> Map.merge(%{
      "max_fee_per_blob_gas" => decimal(transaction.max_fee_per_blob_gas),
      "blob_versioned_hashes" => Enum.map(transaction.blob_versioned_hashes, &Hex.encode_hex/1)
    })
  end

  defp canonical_fields(%V4{} = transaction) do
    transaction
    |> dynamic_fee_fields()
    |> Map.put("authorization_list", Enum.map(transaction.authorization_list, &canonical_authorization/1))
  end

  defp dynamic_fee_fields(transaction) do
    transaction
    |> typed_fields()
    |> Map.merge(%{
      "max_priority_fee_per_gas" => decimal(transaction.max_priority_fee_per_gas),
      "max_fee_per_gas" => decimal(transaction.max_fee_per_gas)
    })
  end

  defp typed_fields(transaction) do
    %{
      "chain_id" => decimal(transaction.chain_id),
      "nonce" => decimal(transaction.nonce),
      "gas_limit" => decimal(transaction.gas_limit),
      "destination" => Hex.encode_hex(transaction.destination),
      "amount" => decimal(transaction.amount),
      "data" => Hex.encode_hex(transaction.data),
      "access_list" => Enum.map(transaction.access_list, &canonical_access_entry/1)
    }
  end

  defp canonical_access_entry({address, storage_keys}) do
    %{
      "address" => Hex.encode_hex(address),
      "storage_keys" => Enum.map(storage_keys, &Hex.encode_hex/1)
    }
  end

  defp canonical_authorization({chain_id, address, nonce, y_parity, r, s}) do
    %{
      "chain_id" => decimal(chain_id),
      "address" => Hex.encode_hex(address),
      "nonce" => decimal(nonce),
      "y_parity" => if(y_parity, do: 1, else: 0),
      "r" => Hex.encode_hex(r),
      "s" => Hex.encode_hex(s)
    }
  end

  defp decimal(integer), do: Integer.to_string(integer)
end

defmodule Cartouche.BlockTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Block
  alias Cartouche.Block.Withdrawal

  doctest Block
  doctest Withdrawal

  # Minimal pre-London block fixture — strips the moduledoc doctest's
  # logsBloom/extraData/etc. down to the smallest set deserialize/1 will
  # tolerate. Pre-London blocks omit baseFeePerGas, withdrawals*, and the
  # Cancun fields entirely on the wire.
  @spec pre_london_params(any()) :: any()
  defp pre_london_params(extra \\ %{}) do
    Map.merge(
      %{
        "number" => "0x989680",
        "hash" => "0xaa20f7bde5be60603f11a45fc4923aab7552be775403fc00c2e6b805e6297dbe",
        "parentHash" => "0x966bf6849da92ff2a0e3db9a371f5b9f07dd6001e2770a4269a5c134f1bf9c4c",
        "nonce" => "0x0000000000000000",
        "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        "logsBloom" => "0x" <> String.duplicate("00", 256),
        "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        "stateRoot" => "0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d",
        "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        "miner" => "0xea674fdde714fd979de3edf0f56aa9716b898ec8",
        "difficulty" => "0x4ea3f27bc",
        "totalDifficulty" => "0x78ed983323d",
        "extraData" => "0x",
        "size" => "0x220",
        "gasLimit" => "0x98705c",
        "gasUsed" => "0x9824b3",
        "timestamp" => "0x5eb01705",
        "transactions" => [],
        "uncles" => []
      },
      extra
    )
  end

  describe "deserialize/1 — fork-tier optional fields (Tasks 63 + 64 + 65)" do
    test "pre-London block: every fork-tier optional field is nil" do
      b = Block.deserialize(pre_london_params())

      # All seven nullable fields default to nil when the wire payload omits them.
      assert b.base_fee_per_gas == nil
      assert b.withdrawals_root == nil
      assert b.withdrawals == nil
      assert b.parent_beacon_block_root == nil
      assert b.blob_gas_used == nil
      assert b.excess_blob_gas == nil
      # mixHash is the only field present pre-London — but the minimal fixture omits it.
      assert b.mix_hash == nil
    end

    test "post-London block: base_fee_per_gas decodes; Shanghai/Cancun fields nil (Task 63)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
            "baseFeePerGas" => "0x6f4f8d96"
          })
        )

      assert b.base_fee_per_gas == 0x6F4F8D96
      assert is_integer(b.base_fee_per_gas)
      assert byte_size(b.mix_hash) == 32
      # Shanghai + Cancun fields still nil at this fork tier.
      assert b.withdrawals_root == nil
      assert b.withdrawals == nil
      assert b.parent_beacon_block_root == nil
      assert b.blob_gas_used == nil
      assert b.excess_blob_gas == nil
    end

    test "post-Shanghai block: withdrawals + withdrawals_root populated (Task 64)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "baseFeePerGas" => "0x6f4f8d96",
            "withdrawalsRoot" => "0x9d56fa5a08e21cd3ff7f8b6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb",
            "withdrawals" => [
              %{
                "index" => "0x4d8f7d",
                "validatorIndex" => "0xc8a5f",
                "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
                "amount" => "0x111c8c2"
              },
              %{
                "index" => "0x4d8f7e",
                "validatorIndex" => "0xc8a60",
                "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
                "amount" => "0x111c8c3"
              }
            ]
          })
        )

      assert byte_size(b.withdrawals_root) == 32
      assert is_list(b.withdrawals)
      assert length(b.withdrawals) == 2
      assert [%Withdrawal{index: 0x4D8F7D} | _] = b.withdrawals
      # Cancun fields still nil at the Shanghai tier.
      assert b.parent_beacon_block_root == nil
      assert b.blob_gas_used == nil
    end

    test "empty withdrawals list deserializes to [] (not nil)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "withdrawalsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
            "withdrawals" => []
          })
        )

      # The boundary between "absent on the wire" (→ nil) and "present but empty"
      # (→ []) — consumers depend on this distinction to detect Shanghai+ blocks
      # with no validator withdrawals in this slot.
      assert b.withdrawals == []
      assert byte_size(b.withdrawals_root) == 32
    end

    test "post-Cancun block: all four Cancun fields populated (Task 65)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
            "baseFeePerGas" => "0x6f4f8d96",
            "withdrawalsRoot" => "0x9d56fa5a08e21cd3ff7f8b6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb",
            "withdrawals" => [],
            "parentBeaconBlockRoot" => "0xb390d63aac03bbef75de888d16bd56b91c9291c2a7e38d36ac24731351522bd1",
            "blobGasUsed" => "0x80000",
            "excessBlobGas" => "0x4a0000"
          })
        )

      assert byte_size(b.parent_beacon_block_root) == 32
      assert b.blob_gas_used == 0x80000
      assert b.excess_blob_gas == 0x4A0000
      assert is_integer(b.blob_gas_used)
      assert is_integer(b.excess_blob_gas)
      assert byte_size(b.mix_hash) == 32
    end

    test "mix_hash decodes when present, regardless of fork tier" do
      mix_hash_hex =
        "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843"

      b = Block.deserialize(pre_london_params(%{"mixHash" => mix_hash_hex}))

      assert b.mix_hash ==
               ~h[0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843]

      assert byte_size(b.mix_hash) == 32
    end
  end

  describe "Cartouche.Block.Withdrawal.deserialize/1 (Task 64)" do
    test "happy path — single withdrawal" do
      w =
        Withdrawal.deserialize(%{
          "index" => "0x4d8f7d",
          "validatorIndex" => "0xc8a5f",
          "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
          "amount" => "0x111c8c2"
        })

      assert w.index == 0x4D8F7D
      assert w.validator_index == 0xC8A5F
      assert w.address == ~h[0x1f9090aae28b8a3dceadf281b0f12828e676c326]
      assert w.amount == 0x111C8C2
      assert byte_size(w.address) == 20
    end

    test "zero-amount boundary" do
      w =
        Withdrawal.deserialize(%{
          "index" => "0x0",
          "validatorIndex" => "0x0",
          "address" => "0x0000000000000000000000000000000000000000",
          "amount" => "0x0"
        })

      assert w.index == 0
      assert w.validator_index == 0
      assert w.amount == 0
      assert byte_size(w.address) == 20
    end

    test "uint64 max amount round-trips as Elixir integer" do
      # Validator pool amounts are uint64-bounded gwei. Exercise the upper
      # boundary to confirm the integer decoder handles full-width values.
      max_uint64 = 0xFFFF_FFFF_FFFF_FFFF

      w =
        Withdrawal.deserialize(%{
          "index" => "0x0",
          "validatorIndex" => "0x0",
          "address" => "0x0000000000000000000000000000000000000000",
          "amount" => "0x" <> Integer.to_string(max_uint64, 16)
        })

      assert w.amount == max_uint64
    end
  end
end

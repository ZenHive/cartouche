defmodule Cartouche.RPC.IntegrationTest do
  @moduledoc """
  Mainnet archive integration tests.

  Hits a real mainnet archive node (default `http://127.0.0.1:8545`, override
  via `CARTOUCHE_LIVE_NODE_URL`). Excluded from `mix test` by default; opt in
  via `mix integration` or `mix test --include integration`.

  Anchor blocks/txs/contracts are pinned to historical mainnet data — the
  chain is immutable, so assertions are deterministic forever.
  """
  use ExUnit.Case, async: true

  import Cartouche.Test.Live, only: [live_opts: 0]

  alias Cartouche.Transaction.V1

  @moduletag :integration

  setup_all do
    Cartouche.Test.Live.assert_node_available!()
    :ok
  end

  # ───────────────────────── anchor data ─────────────────────────

  # Pre-London anchor (block 10,000,000)
  @pre_london_block 10_000_000
  @pre_london_hash <<0xAA20F7BDE5BE60603F11A45FC4923AAB7552BE775403FC00C2E6B805E6297DBE::256>>
  @pre_london_parent <<0x966BF6849DA92FF2A0E3DB9A371F5B9F07DD6001E2770A4269A5C134F1BF9C4C::256>>
  @pre_london_miner <<0xEA674FDDE714FD979DE3EDF0F56AA9716B898EC8::160>>
  @pre_london_gas_limit 0x98705C
  @pre_london_gas_used 0x9824B3
  @pre_london_timestamp 0x5EB01705

  # Post-London / pre-Shanghai (block 15,000,000)
  @post_london_block 15_000_000
  @post_london_hash <<0x9A71A95BE3FE957457B11817587E5AF4C7E24836D5B383C430FF25B9286A457F::256>>
  @post_london_parent <<0x93A8A23A2F5296DB7251AB4C5E9B10BDC5A6C9C4ED56FB230DC729D3DC03A138::256>>
  @post_london_miner <<0xEA674FDDE714FD979DE3EDF0F56AA9716B898EC8::160>>
  @post_london_gas_limit 0x1C9C380
  @post_london_gas_used 0x1C9BED2
  @post_london_timestamp 0x62B12CC4

  # Post-Shanghai / pre-Cancun (block 18,000,000)
  @post_shanghai_block 18_000_000
  @post_shanghai_hash <<0x95B198E154ACBFC64109DFD22D8224FE927FD8DFDEDFAE01587674482BA4BAF3::256>>
  @post_shanghai_parent <<0x198723E0DDF20153951C6304093CBD97FD306C5DB03287C5586C0430A986080D::256>>
  @post_shanghai_miner <<0xDAFEA492D9C6733AE3D56B7ED1ADB60692C98BC5::160>>
  @post_shanghai_gas_limit 0x1C9C380
  @post_shanghai_gas_used 0xF7E9AB
  @post_shanghai_timestamp 0x64EA268F

  # Post-Cancun (block 20,000,000)
  @post_cancun_block 20_000_000
  @post_cancun_hash <<0xD24FD73F794058A3807DB926D8898C6481E902B7EDB91CE0D479D6760F276183::256>>
  @post_cancun_parent <<0xB390D63AAC03BBEF75DE888D16BD56B91C9291C2A7E38D36AC24731351522BD1::256>>
  @post_cancun_miner <<0x95222290DD7278AA3DDD389CC1E1D165CC4BAFE5::160>>
  @post_cancun_gas_limit 0x1C9C380
  @post_cancun_gas_used 0xA9371C
  @post_cancun_timestamp 0x665BA27F

  # Type-0 (legacy) receipt anchor — first tx of block 10,000,000, simple ETH transfer
  @type_0_receipt_hash <<0x4A1E3E3A2AA4AA79A777D0AE3E2C3A6DE158226134123F6C14334964C6EC70CF::256>>
  @type_0_receipt_block 10_000_000
  @type_0_receipt_gas_used 0x5208

  # Type-2 (EIP-1559) receipt anchor — first tx of block 18,000,000, has 1 log
  @type_2_receipt_hash <<0x16E199673891DF518E25DB2EF5320155DA82A3DD71A677E7D84363251885D133::256>>
  @type_2_receipt_block 18_000_000
  @type_2_receipt_gas_used 0xEC18
  @type_2_receipt_effective_gas_price 0x54A485839

  # Type-3 (EIP-4844 blob) receipt anchor — blob tx after Dencun activation.
  @type_3_receipt_hash <<0xBBC6C82F2D81479E2A7FFA61529FBA4BD4671A8AEFB69A261F6A9B07E46B7F79::256>>
  @type_3_receipt_block 19_449_343
  @type_3_receipt_gas_used 0x2A8E4
  @type_3_receipt_blob_gas_used 0x20_000
  @type_3_receipt_blob_gas_price 0x1

  # WETH9 anchor at block 18,000,000
  @weth9 <<0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2::160>>
  @weth9_anchor_block 18_000_000
  @weth9_code_hash <<0xD0A06B12AC47863B5C7BE4185C2DEAAD1C61557033F56C7D4EA74429CBB25E23::256>>
  @weth9_code_byte_length 3124
  @weth9_balance 0x2B30B5DBA159D35B4FEC1
  @weth9_nonce 0x1
  @weth9_total_supply 0x2B30B5DBA159D35B4FEC1

  # feeHistory anchor at block 18,000,000
  @fee_history_newest_block 18_000_000
  @fee_history_block_count 4
  @fee_history_oldest_block 0x112A87D

  describe "chain-level reads" do
    test "eth_chainId returns 1 (mainnet)" do
      assert {:ok, 1} = Cartouche.RPC.eth_chain_id(live_opts())
    end

    test "eth_blockNumber is past archive baseline" do
      assert {:ok, n} = Cartouche.RPC.eth_block_number(live_opts())
      assert is_integer(n)
      assert n > 19_000_000
    end

    test "eth_gasPrice > 0" do
      assert {:ok, p} = Cartouche.RPC.gas_price(live_opts())
      assert is_integer(p)
      assert p > 0
    end

    test "eth_maxPriorityFeePerGas >= 0" do
      assert {:ok, p} = Cartouche.RPC.max_priority_fee_per_gas(live_opts())
      assert is_integer(p)
      assert p >= 0
    end
  end

  describe "block reads at fork-tier anchors" do
    test "pre-London (block 10,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@pre_london_block, live_opts())
      assert b.number == @pre_london_block
      assert b.hash == @pre_london_hash
      assert b.parent_hash == @pre_london_parent
      assert b.miner == @pre_london_miner
      assert b.gas_limit == @pre_london_gas_limit
      assert b.gas_used == @pre_london_gas_used
      assert b.timestamp == @pre_london_timestamp
    end

    test "pre-London (block 10,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@pre_london_hash, live_opts())
      assert b.number == @pre_london_block
      assert b.hash == @pre_london_hash
    end

    test "post-London (block 15,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_london_block, live_opts())
      assert b.number == @post_london_block
      assert b.hash == @post_london_hash
      assert b.parent_hash == @post_london_parent
      assert b.miner == @post_london_miner
      assert b.gas_limit == @post_london_gas_limit
      assert b.gas_used == @post_london_gas_used
      assert b.timestamp == @post_london_timestamp

      assert is_integer(b.base_fee_per_gas)
      assert b.base_fee_per_gas > 0
    end

    test "post-London (block 15,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@post_london_hash, live_opts())
      assert b.number == @post_london_block
      assert b.hash == @post_london_hash
    end

    test "post-Shanghai (block 18,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_shanghai_block, live_opts())
      assert b.number == @post_shanghai_block
      assert b.hash == @post_shanghai_hash
      assert b.parent_hash == @post_shanghai_parent
      assert b.miner == @post_shanghai_miner
      assert b.gas_limit == @post_shanghai_gas_limit
      assert b.gas_used == @post_shanghai_gas_used
      assert b.timestamp == @post_shanghai_timestamp

      assert is_list(b.withdrawals)
      assert byte_size(b.withdrawals_root) == 32
      # The 18M anchor is well past Shanghai (block ≥ 17,034,870), so a real
      # mainnet block at this height carries at least one validator withdrawal.
      assert [%Cartouche.Block.Withdrawal{} | _] = b.withdrawals
    end

    test "post-Shanghai (block 18,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@post_shanghai_hash, live_opts())
      assert b.number == @post_shanghai_block
      assert b.hash == @post_shanghai_hash
    end

    test "post-Cancun (block 20,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_cancun_block, live_opts())
      assert b.number == @post_cancun_block
      assert b.hash == @post_cancun_hash
      assert b.parent_hash == @post_cancun_parent
      assert b.miner == @post_cancun_miner
      assert b.gas_limit == @post_cancun_gas_limit
      assert b.gas_used == @post_cancun_gas_used
      assert b.timestamp == @post_cancun_timestamp

      assert byte_size(b.parent_beacon_block_root) == 32
      assert is_integer(b.blob_gas_used)
      assert is_integer(b.excess_blob_gas)
      assert byte_size(b.mix_hash) == 32
    end

    test "post-Cancun (block 20,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@post_cancun_hash, live_opts())
      assert b.number == @post_cancun_block
      assert b.hash == @post_cancun_hash
    end
  end

  describe "receipt reads" do
    test "type-0 (legacy) receipt at block 10,000,000" do
      assert {:ok, r} = Cartouche.RPC.get_trx_receipt(@type_0_receipt_hash, live_opts())
      assert r.transaction_hash == @type_0_receipt_hash
      assert r.block_number == @type_0_receipt_block
      assert r.status == 1
      assert r.type == 0
      assert r.gas_used == @type_0_receipt_gas_used
      assert r.logs == []
    end

    test "type-2 (EIP-1559) receipt at block 18,000,000" do
      assert {:ok, r} = Cartouche.RPC.get_trx_receipt(@type_2_receipt_hash, live_opts())
      assert r.transaction_hash == @type_2_receipt_hash
      assert r.block_number == @type_2_receipt_block
      assert r.status == 1
      assert r.type == 2
      assert r.gas_used == @type_2_receipt_gas_used
      assert r.effective_gas_price == @type_2_receipt_effective_gas_price
      assert match?([_], r.logs)
      assert r.blob_gas_used == nil
      assert r.blob_gas_price == nil
    end

    test "type-3 (EIP-4844 blob) receipt at block 19,449,343" do
      assert {:ok, r} = Cartouche.RPC.get_trx_receipt(@type_3_receipt_hash, live_opts())
      assert r.transaction_hash == @type_3_receipt_hash
      assert r.block_number == @type_3_receipt_block
      assert r.status == 1
      assert r.type == 3
      assert r.gas_used == @type_3_receipt_gas_used

      assert is_integer(r.blob_gas_used)
      assert r.blob_gas_used == @type_3_receipt_blob_gas_used
      assert r.blob_gas_used > 0

      assert is_integer(r.blob_gas_price)
      assert r.blob_gas_price == @type_3_receipt_blob_gas_price
      assert r.blob_gas_price > 0
    end
  end

  describe "account/code reads (WETH9 at block 18,000,000)" do
    test "eth_getCode returns pinned bytecode" do
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, code} = Cartouche.RPC.get_code(@weth9, opts)
      assert is_binary(code)
      assert byte_size(code) == @weth9_code_byte_length
      assert <<first, _::binary>> = code
      # 0x60 = PUSH1, valid EVM bytecode prefix
      assert first == 0x60
      assert Cartouche.Hash.keccak(code) == @weth9_code_hash
    end

    test "eth_getBalance pins to historical balance" do
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, balance} = Cartouche.RPC.get_balance(@weth9, opts)
      assert balance == @weth9_balance
    end

    test "eth_getTransactionCount pins to historical nonce" do
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, nonce} = Cartouche.RPC.get_transaction_count(@weth9, opts)
      assert nonce == @weth9_nonce
    end
  end

  describe "speculative reads" do
    test "eth_call WETH9.totalSupply() at block 18,000,000" do
      # selector for totalSupply() => 0x18160ddd
      data = <<0x18, 0x16, 0x0D, 0xDD>>
      trx = V1.new(0, {0, :gwei}, 100_000, @weth9, 0, data)

      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, result} = Cartouche.RPC.call_trx(trx, opts)
      assert is_binary(result)
      assert byte_size(result) == 32
      assert :binary.decode_unsigned(result) == @weth9_total_supply
    end

    test "eth_estimateGas for a simple ETH transfer (~21,000)" do
      # transfer 0 wei to a non-zero EOA, no calldata → intrinsic 21,000 gas
      to = <<0x000000000000000000000000000000000000DEAD::160>>
      trx = V1.new(0, {1, :gwei}, 30_000, to, 0, <<>>)

      assert {:ok, gas} = Cartouche.RPC.estimate_gas(trx, live_opts())
      assert is_integer(gas)
      assert gas == 21_000
    end
  end

  describe "fee history" do
    test "eth_feeHistory at block 18,000,000 returns expected shape" do
      opts =
        live_opts()
        |> Keyword.put(:block_count, @fee_history_block_count)
        |> Keyword.put(:newest_block, "0x#{Integer.to_string(@fee_history_newest_block, 16)}")
        |> Keyword.put(:reward_percentiles, [25.0, 50.0, 75.0])

      assert {:ok, fh} = Cartouche.RPC.fee_history(opts)

      assert fh.oldest_block == @fee_history_oldest_block
      # block_count + 1
      assert length(fh.base_fee_per_gas) == @fee_history_block_count + 1
      assert length(fh.gas_used_ratio) == @fee_history_block_count
      assert length(fh.reward) == @fee_history_block_count
      assert Enum.all?(fh.reward, fn inner -> length(inner) == 3 end)
    end
  end
end

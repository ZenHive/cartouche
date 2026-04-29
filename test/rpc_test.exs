defmodule Cartouche.RPCTest do
  use ExUnit.Case, async: false
  use Cartouche.Hex

  doctest Cartouche.RPC

  defmodule CaptureClient do
    @moduledoc false
    # Delegates to `Cartouche.Test.Client` so doctest fixtures still work,
    # and `send`s the decoded JSON-RPC request body back to the test pid
    # registered as `:cartouche_rpc_capture` for wire-format assertions.
    def request(%Finch.Request{body: body} = req, finch_name, opts) do
      decoded = Jason.decode!(body)
      send(:cartouche_rpc_capture, {:rpc_request, decoded})
      Cartouche.Test.Client.request(req, finch_name, opts)
    end
  end

  describe "block-param wire encoding" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, :client)
      Application.put_env(:cartouche, :client, CaptureClient)
      on_exit(fn -> Application.put_env(:cartouche, :client, prev) end)
      :ok
    end

    test "get_block_by_number/2 encodes integer as lowercase quantity string" do
      {:ok, %Cartouche.Block{}} = Cartouche.RPC.get_block_by_number(55)

      assert_received {:rpc_request, %{"method" => "eth_getBlockByNumber", "params" => ["0x37", false]}}
    end

    test "get_block_by_number/2 passes string tag through unchanged" do
      {:ok, %Cartouche.Block{}} = Cartouche.RPC.get_block_by_number("latest")
      assert_received {:rpc_request, %{"params" => ["latest", false]}}
    end

    test "get_block_by_number/2 passes hex string through unchanged" do
      {:ok, %Cartouche.Block{}} = Cartouche.RPC.get_block_by_number("0x37")
      assert_received {:rpc_request, %{"params" => ["0x37", false]}}
    end

    test "get_balance/2 normalizes integer :block_number opt" do
      addr = ~h[0x407d73d8a49eeb85d32cf465507dd71d507100c1]
      {:ok, _} = Cartouche.RPC.get_balance(addr, block_number: 55)

      assert_received {:rpc_request, %{"method" => "eth_getBalance", "params" => [_addr_hex, "0x37"]}}
    end

    test "get_nonce/2 normalizes integer :block_number opt zero to '0x0'" do
      addr = ~h[0x407d73d8a49eeb85d32cf465507dd71d507100c1]
      {:ok, _} = Cartouche.RPC.get_nonce(addr, block_number: 0)

      assert_received {:rpc_request, %{"method" => "eth_getTransactionCount", "params" => [_addr_hex, "0x0"]}}
    end
  end
end

defmodule Cartouche.RPCTest do
  use ExUnit.Case, async: false
  use Cartouche.Hex

  import ExUnit.CaptureLog

  alias Cartouche.Transaction.V1

  doctest Cartouche.RPC

  defmodule CustomRevertClient do
    @moduledoc false

    @revert_data "0x" <> Base.encode16(ABI.encode("Cool(uint256,string)", [1, "cat"]))

    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      id = Jason.decode!(body)["id"]

      response =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "error" => %{"code" => 3, "message" => "execution reverted", "data" => @revert_data},
          "id" => id
        })

      {:ok, %Finch.Response{status: 200, body: response}}
    end
  end

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

  defmodule PanicClient do
    @moduledoc false

    @panic_data "0x" <> Base.encode16(<<0x4E487B71::32, 0::248, 0x11>>)

    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      id = Jason.decode!(body)["id"]

      response =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "error" => %{"code" => 3, "message" => "execution reverted", "data" => @panic_data},
          "id" => id
        })

      {:ok, %Finch.Response{status: 200, body: response}}
    end
  end

  defmodule PanicCodeClient do
    @moduledoc false

    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      id = Jason.decode!(body)["id"]
      panic_code = Process.get(:panic_code)
      panic_data = "0x" <> Base.encode16(<<0x4E487B71::32, 0::248, panic_code>>)

      response =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "error" => %{"code" => 3, "message" => "execution reverted", "data" => panic_data},
          "id" => id
        })

      {:ok, %Finch.Response{status: 200, body: response}}
    end
  end

  defmodule NonHexRevertClient do
    @moduledoc false

    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      id = Jason.decode!(body)["id"]

      response =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "error" => %{"code" => 3, "message" => "execution reverted", "data" => "not hex"},
          "id" => id
        })

      {:ok, %Finch.Response{status: 200, body: response}}
    end
  end

  defmodule InvalidJsonRpcClient do
    @moduledoc false

    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      id = Jason.decode!(body)["id"]
      response = Jason.encode!(%{"jsonrpc" => "2.0", "unexpected" => nil, "id" => id})
      {:ok, %Finch.Response{status: 200, body: response}}
    end
  end

  defmodule TransportErrorClient do
    @moduledoc false

    def request(_request, _finch_name, _opts), do: {:error, :closed}
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

  describe "send_rpc/3 response handling" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, :client)
      Application.put_env(:cartouche, :client, CaptureClient)
      on_exit(fn -> Application.put_env(:cartouche, :client, prev) end)
      :ok
    end

    test "invalid JSON-RPC responses return the sentinel error" do
      assert {:error, %{code: -999, message: "invalid JSON-RPC response"}} =
               Cartouche.RPC.send_rpc("net_version", [], client: InvalidJsonRpcClient)
    end

    test "invalid params errors log the outbound request" do
      log =
        capture_log(fn ->
          assert {:error, %{code: -32_602, message: "Failed to decode transaction"}} =
                   1
                   |> V1.new({100, :gwei}, 100_000, <<13::160>>, {2, :wei}, <<1, 2, 3>>)
                   |> Cartouche.RPC.call_trx()
        end)

      assert log =~ "Invalid JSON-PRC request"
      assert log =~ "eth_call"
    end

    test "known Panic(uint256) revert data is decoded without custom ABI metadata" do
      assert {:error, %{code: 3, message: "execution reverted", revert: <<0x4E487B71::32, 0::248, 0x11>>} = error} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 client: PanicClient
               )

      refute Map.has_key?(error, :error_abi)
    end

    test "custom revert errors expose ABI name and decoded params" do
      assert {:error, %{error_abi: "Cool(uint256,string)", error_params: [1, "cat"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "custom revert errors are decoded through selector-prefixed revert data" do
      revert_data = ABI.encode("Cool(uint256,string)", [1, "cat"])

      assert {:ok, %{error: "Cool", args: [1, "cat"]}} =
               ABI.decode_error(revert_data, ["Cool(uint256,string)"])

      assert {:error, %{error_abi: "Cool(uint256,string)", error_params: [1, "cat"]}} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>),
                 errors: ["Cool(uint256,string)"]
               )
    end

    test "Panic(uint256) reverts keep the raw revert bytes for recognized panic codes" do
      for code <- [0x01, 0x11, 0x12, 0x21, 0x32, 0x41, 0x51] do
        Process.put(:panic_code, code)

        assert {:error, %{revert: <<0x4E487B71::32, 0::248, ^code>>} = error} =
                 Cartouche.RPC.call_trx(
                   V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                   client: PanicCodeClient
                 )

        refute Map.has_key?(error, :error_abi)
      end
    end

    test "non-hex revert data keeps only the base RPC error fields" do
      assert {:error, %{code: 3, message: "execution reverted"} = error} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 client: NonHexRevertClient
               )

      refute Map.has_key?(error, :revert)
      refute Map.has_key?(error, :error_abi)
    end

    test "transport errors are normalized before JSON-RPC decoding" do
      assert {:error, "[Cartouche] Unknown error: :closed"} =
               Cartouche.RPC.send_rpc("net_version", [], client: TransportErrorClient)
    end
  end

  describe "call params and tracing helpers" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, :client)
      Application.put_env(:cartouche, :client, CaptureClient)
      on_exit(fn -> Application.put_env(:cartouche, :client, prev) end)
      :ok
    end

    test "trace_call_many/2 accepts explicit per-transaction from overrides" do
      trx = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      from = <<2::160>>

      assert {:ok, [_trace | _]} = Cartouche.RPC.trace_call_many([{trx, from}], block_number: 55)

      assert_received {:rpc_request,
                       %{
                         "method" => "trace_callMany",
                         "params" => [
                           [
                             [
                               %{"from" => "0x0000000000000000000000000000000000000002"},
                               ["trace"]
                             ]
                           ],
                           "0x37"
                         ]
                       }}
    end

    test "trace_call_many/2 uses the shared :from option for bare transactions" do
      trx = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)

      assert {:ok, [_trace | _]} = Cartouche.RPC.trace_call_many([trx], from: <<3::160>>)

      assert_received {:rpc_request,
                       %{
                         "method" => "trace_callMany",
                         "params" => [
                           [
                             [
                               %{"from" => "0x0000000000000000000000000000000000000003"},
                               ["trace"]
                             ]
                           ],
                           "latest"
                         ]
                       }}
    end

    test "debug_trace_call/2 normalizes integer block params" do
      trx = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)

      assert {:ok, %Cartouche.DebugTrace{}} = Cartouche.RPC.debug_trace_call(trx, block_number: 55)

      assert_received {:rpc_request, %{"method" => "debug_traceCall", "params" => [_call, "0x37"]}}
    end

    test "call_trx/2 sends Call params without transaction fee fields" do
      call = Cartouche.Transaction.Call.new(<<1::160>>, <<0, 1>>, from: <<4::160>>, gas: 21_000, value: 7)

      assert {:ok, <<0xCC>>} = Cartouche.RPC.call_trx(call, from: <<5::160>>, block_number: 55)

      assert_received {:rpc_request,
                       %{
                         "method" => "eth_call",
                         "params" => [
                           %{
                             "from" => "0x0000000000000000000000000000000000000004",
                             "to" => "0x0000000000000000000000000000000000000001",
                             "gas" => "0x5208",
                             "value" => "0x7",
                             "data" => "0x0001"
                           },
                           "0x37"
                         ]
                       }}
    end

    test "call_trx/2 attaches trace output when revert tracing succeeds" do
      assert {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>, trace: _}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(trace_reverts: true)
    end

    test "call_trx/2 uses debug tracing when requested" do
      assert {:error, %{code: 3, message: "execution reverted", trace: %Cartouche.DebugTrace{}}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(trace_reverts: true, debug_trace: true)
    end
  end

  describe "prepare_trx/3 branches" do
    test "execute_trx/3 prepares, signs, and broadcasts a legacy transaction" do
      signer_proc = Cartouche.Test.Signer.start_signer()

      assert {:ok, trx_id} =
               Cartouche.RPC.execute_trx(<<1::160>>, <<>>,
                 gas_price: {50, :gwei},
                 gas_limit: 100_000,
                 value: 0,
                 nonce: 5,
                 signer: signer_proc,
                 chain_id: :goerli
               )

      assert <<5, _gas_price::64, 100_000::24, _to::binary-size(20)>> = trx_id
    end

    test "mismatched explicit transaction type and gas options raise" do
      assert_raise RuntimeError, "mismatched transaction type and gas price settings", fn ->
        Cartouche.RPC.prepare_trx(<<1::160>>, <<>>, trx_type: :v1, base_fee: {1, :gwei})
      end
    end

    test "surfaces missing fee history data when base fee cannot be resolved" do
      defmodule MissingFeeHistoryClient do
        @moduledoc false

        def request(%Finch.Request{body: body}, _finch_name, _opts) do
          id = Jason.decode!(body)["id"]
          response = Jason.encode!(%{"jsonrpc" => "2.0", "result" => %{}, "id" => id})
          {:ok, %Finch.Response{status: 200, body: response}}
        end
      end

      assert_raise FunctionClauseError, fn ->
        Cartouche.RPC.prepare_trx(<<1::160>>, <<>>, client: MissingFeeHistoryClient)
      end
    end
  end
end

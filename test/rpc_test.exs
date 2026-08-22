defmodule Cartouche.RPCTest do
  use ExUnit.Case, async: false
  use Cartouche.Hex

  import ExUnit.CaptureLog

  alias Cartouche.Transaction.V1

  doctest Cartouche.RPC

  defmodule UnencodableStruct do
    @moduledoc false
    defstruct [:value]
  end

  # Each mock is a Req function plug (`fun(conn) -> conn`). It runs in the process
  # that calls `Req.request/1` — the test pid for direct calls here — so wire
  # captures via `send(self(), ...)` and `Process.get/put` work with no Req.Test
  # ownership ceremony. Request bodies are read with `Req.Test.raw_body/1`
  # (idempotent — it reads the adapter's stored body, not a consumable stream),
  # and responses are returned with `Req.Test.json/2`.
  @doc false
  def decode_id(conn) do
    conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!() |> Map.fetch!("id")
  end

  defmodule CaptureClient do
    @moduledoc false
    # Delegates to `Cartouche.Test.Client` so doctest fixtures still work,
    # and `send`s the decoded JSON-RPC request body back to the test pid
    # registered as `:cartouche_rpc_capture` for wire-format assertions.
    def call(conn) do
      decoded = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(:cartouche_rpc_capture, {:rpc_request, decoded})
      Cartouche.Test.Client.call(conn)
    end
  end

  defmodule PanicClient do
    @moduledoc false

    @panic_data "0x" <> Base.encode16(<<0x4E487B71::32, 0::248, 0x11>>)

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => @panic_data},
        "id" => id
      })
    end
  end

  defmodule PanicCodeClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)
      panic_code = Process.get(:panic_code)
      panic_data = "0x" <> Base.encode16(<<0x4E487B71::32, 0::248, panic_code>>)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => panic_data},
        "id" => id
      })
    end
  end

  defmodule NonHexRevertClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => "not hex"},
        "id" => id
      })
    end
  end

  defmodule OverloadedErrorClient do
    @moduledoc false

    @revert_data "0x" <> Base.encode16(ABI.encode("Overloaded(address)", [<<1::160>>]))

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => @revert_data},
        "id" => id
      })
    end
  end

  defmodule InvalidJsonRpcClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "unexpected" => nil, "id" => id})
    end
  end

  defmodule TransportErrorClient do
    @moduledoc false

    def call(conn), do: Req.Test.transport_error(conn, :closed)
  end

  describe "block-param wire encoding" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &CaptureClient.call/1)
      on_exit(fn -> Application.put_env(:cartouche, Cartouche.RPC, prev) end)
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

    test "fee_history/1 normalizes integer :newest_block opt" do
      {:ok, %Cartouche.FeeHistory{}} = Cartouche.RPC.fee_history(newest_block: 55)

      assert_received {:rpc_request, %{"method" => "eth_feeHistory", "params" => [1, "0x37", []]}}
    end
  end

  describe "send_rpc/3 response handling" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &CaptureClient.call/1)
      on_exit(fn -> Application.put_env(:cartouche, Cartouche.RPC, prev) end)
      :ok
    end

    test "invalid JSON-RPC responses return the sentinel error" do
      assert {:error, %{code: -999, message: "invalid JSON-RPC response"}} =
               Cartouche.RPC.send_rpc("net_version", [], req_options: [plug: &InvalidJsonRpcClient.call/1])
    end

    test "invalid hex results return :invalid_hex" do
      assert :invalid_hex =
               Cartouche.RPC.send_rpc("net_version", [],
                 decode: :hex,
                 req_options: [plug: &Cartouche.Test.InvalidHexResultClient.call/1]
               )
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
                 req_options: [plug: &PanicClient.call/1]
               )

      refute Map.has_key?(error, :error_abi)
    end

    test "custom revert errors expose ABI name and decoded params" do
      assert {:error, %{error_abi: "Cool(uint256,string)", error_params: [1, "cat"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "overloaded custom errors map decoded names back by selector" do
      assert {:error, %{error_abi: "Overloaded(address)", error_params: [<<1::160>>]}} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 req_options: [plug: &OverloadedErrorClient.call/1],
                 errors: ["Overloaded(uint256)", "Overloaded(address)"]
               )
    end

    test "Panic(uint256) reverts keep the raw revert bytes for recognized panic codes" do
      for code <- [0x00, 0x01, 0x11, 0x12, 0x21, 0x22, 0x31, 0x32, 0x41, 0x51] do
        Process.put(:panic_code, code)

        assert {:error, %{revert: <<0x4E487B71::32, 0::248, ^code>>} = error} =
                 Cartouche.RPC.call_trx(
                   V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                   req_options: [plug: &PanicCodeClient.call/1]
                 )

        refute Map.has_key?(error, :error_abi)
      end
    end

    test "Panic(uint256) private descriptions match Solidity panic codes" do
      source = File.read!("lib/cartouche/rpc.ex")

      assert source =~
               ~s|defp classify_decoded_error("Panic", [0x12], _errors, _data), do: {:ok, "division or modulo by zero", nil}|

      assert source =~
               ~s|defp classify_decoded_error("Panic", [0x21], _errors, _data), do: {:ok, "failed to convert value to enum", nil}|
    end

    test "non-hex revert data keeps only the base RPC error fields" do
      assert {:error, %{code: 3, message: "execution reverted"} = error} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 req_options: [plug: &NonHexRevertClient.call/1]
               )

      refute Map.has_key?(error, :revert)
      refute Map.has_key?(error, :error_abi)
    end

    test "transport errors are normalized before JSON-RPC decoding" do
      assert {:error, "[Cartouche] HTTP client error: :closed"} =
               Cartouche.RPC.send_rpc("net_version", [], req_options: [plug: &TransportErrorClient.call/1])
    end
  end

  describe "send_rpc/3 invalid params" do
    test "returns invalid_params for non-UTF-8 binary method" do
      assert {:error, {:invalid_params, %Jason.EncodeError{}}} = Cartouche.RPC.send_rpc(<<255>>, [])
    end

    test "returns invalid_params for tuple params" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               Cartouche.RPC.send_rpc("net_version", [{:tuple, :param}])
    end

    test "returns invalid_params for atom-keyed map params with non-JSON values" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               Cartouche.RPC.send_rpc("net_version", [%{not_a_json_key: self()}])
    end

    test "returns invalid_params for custom structs without Jason encoders" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               Cartouche.RPC.send_rpc("net_version", [%UnencodableStruct{value: 1}])
    end
  end

  describe "call params and tracing helpers" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &CaptureClient.call/1)
      on_exit(fn -> Application.put_env(:cartouche, Cartouche.RPC, prev) end)
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

        def call(conn) do
          id = Cartouche.RPCTest.decode_id(conn)
          Req.Test.json(conn, %{"jsonrpc" => "2.0", "result" => %{}, "id" => id})
        end
      end

      assert_raise FunctionClauseError, fn ->
        Cartouche.RPC.prepare_trx(<<1::160>>, <<>>, req_options: [plug: &MissingFeeHistoryClient.call/1])
      end
    end
  end

  describe "revert-error classification" do
    # The compiler-defined `Error(string)` is never in the caller's `:errors`
    # list; hieroglyph decodes it through a built-in fallback that fires for any
    # candidate list. Attributing it back to a candidate labelled a plain
    # `require(x, "msg")` revert with an unrelated ABI entry.
    test "an Error(string) revert is labelled Error(string), not a caller-supplied entry" do
      assert {:error, %{error_abi: "Error(string)", error_params: ["Dai/insufficient-balance"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<14::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "an Error(string) revert is decoded with no caller-supplied :errors" do
      assert {:error, %{error_abi: "Error(string)", error_params: ["Dai/insufficient-balance"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<14::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx()
    end

    test "a custom error still maps to its own ABI entry" do
      assert {:error, %{error_abi: "Cool(uint256,string)", error_params: [1, "cat"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "an unlisted custom-error selector is not attributed to an unrelated entry" do
      assert {:error, revert_error} =
               1
               |> V1.new({100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])

      refute Map.has_key?(revert_error, :error_abi)
      refute Map.has_key?(revert_error, :error_params)
      assert revert_error.revert == <<0x3D, 0x73, 0x8B, 0x2E>>
    end
  end
end

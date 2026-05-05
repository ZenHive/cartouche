defmodule Cartouche.FilterTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Filter.Log

  doctest Cartouche.Filter

  defmodule ExpiredFilterClient do
    @moduledoc false
    def request(%Finch.Request{body: body}, _finch_name, _opts) do
      %{"method" => method, "params" => params, "id" => id} = Jason.decode!(body)

      response =
        case {method, params} do
          {"eth_newFilter", _} ->
            filter_id =
              case Process.get(:new_filter_count, 0) do
                0 -> "0xf11735"
                _ -> "0xf11736"
              end

            Process.put(:new_filter_count, Process.get(:new_filter_count, 0) + 1)
            %{jsonrpc: "2.0", result: filter_id, id: id}

          {"eth_getFilterChanges", ["0xf11735"]} ->
            Process.put(:expired_seen, true)
            %{jsonrpc: "2.0", error: %{code: -32_000, message: "filter not found"}, id: id}

          {"eth_getFilterChanges", ["0xf11736"]} ->
            %{jsonrpc: "2.0", result: Cartouche.Test.Client.eth_getFilterChanges("0xf11735"), id: id}
        end

      {:ok, %Finch.Response{status: 200, body: Jason.encode!(response)}}
    end
  end

  test "add a filter and get events" do
    extra_data = %{some_key: "some value"}

    {:ok, _filter_pid} =
      Cartouche.Filter.start_link(
        name: MyFilter,
        address: <<1::160>>,
        events: ["Transfer(address indexed from, address indexed to, uint amount)"],
        check_delay: 300,
        extra_data: extra_data
      )

    Cartouche.Filter.listen(MyFilter)

    :timer.sleep(600)

    log =
      %{
        "address" => "0xb5a5f22694352c15b00323844ad545abb2b11028",
        "blockHash" => "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        "blockNumber" => "0x5d12ab",
        "data" => "0x00000000000000000000000000000000000000000000000000000004a817c800",
        "logIndex" => "0x0",
        "removed" => false,
        "topics" => [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        "transactionHash" => "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        "transactionIndex" => "0x3"
      }
      |> Log.deserialize()
      |> Map.put(:extra_data, extra_data)

    assert_received {:event,
                     {"Transfer",
                      %{
                        "amount" => 20_000_000_000,
                        "from" => ~h[b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
                        "to" => ~h[7795126b3ae468f44c901287de98594198ce38ea]
                      }}, ^log}

    assert_received {:log, ^log}
  end

  test "recreates filter when ethereum node reports expired filter" do
    extra_data = %{some_key: "some value"}

    log =
      %{
        "address" => "0xb5a5f22694352c15b00323844ad545abb2b11028",
        "blockHash" => "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        "blockNumber" => "0x5d12ab",
        "data" => "0x00000000000000000000000000000000000000000000000000000004a817c800",
        "logIndex" => "0x0",
        "removed" => false,
        "topics" => [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        "transactionHash" => "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        "transactionIndex" => "0x3"
      }
      |> Log.deserialize()
      |> Map.put(:extra_data, extra_data)

    {:ok, filter_pid} =
      Cartouche.Filter.start_link(
        name: ExpiredFilter,
        address: <<1::160>>,
        events: ["Transfer(address indexed from, address indexed to, uint amount)"],
        check_delay: 20,
        extra_data: extra_data,
        rpc_opts: [client: ExpiredFilterClient]
      )

    Cartouche.Filter.listen(ExpiredFilter)

    assert_receive {:event, {"Transfer", _}, ^log}, 500
    assert_receive {:log, ^log}, 500

    assert {:dictionary, dictionary} = Process.info(filter_pid, :dictionary)
    assert Keyword.get(dictionary, :expired_seen) == true
    assert Keyword.get(dictionary, :new_filter_count, 0) >= 2
  end
end

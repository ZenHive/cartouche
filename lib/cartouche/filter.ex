defmodule Cartouche.Filter do
  @moduledoc """
  A system to create an Ethereum log filter and have
  parsed events passed back to registered processes.
  """

  use GenServer
  use Cartouche.Hex

  alias Cartouche.RPC

  require Logger

  @check_delay 3000

  defmodule Log do
    @moduledoc false
    defstruct [
      :address,
      :block_hash,
      :block_number,
      :data,
      :log_index,
      :removed,
      :topics,
      :transaction_hash,
      :transaction_index,
      :extra_data
    ]

    @type t :: %__MODULE__{
            address: binary(),
            block_hash: binary(),
            block_number: non_neg_integer(),
            data: binary(),
            log_index: non_neg_integer(),
            removed: boolean(),
            topics: [binary()],
            transaction_hash: binary(),
            transaction_index: non_neg_integer(),
            extra_data: term()
          }

    @doc false
    @spec deserialize(map()) :: t()
    def deserialize(%{
          "address" => address,
          "blockHash" => block_hash,
          "blockNumber" => block_number,
          "data" => data,
          "logIndex" => log_index,
          "removed" => removed,
          "topics" => topics,
          "transactionHash" => transaction_hash,
          "transactionIndex" => transaction_index
        }) do
      %__MODULE__{
        address: Hex.decode_address!(address),
        block_hash: Hex.decode_word!(block_hash),
        block_number: Hex.decode_hex_number!(block_number),
        data: from_hex!(data),
        log_index: Hex.decode_hex_number!(log_index),
        removed: removed,
        topics: Enum.map(topics, &Hex.decode_word!/1),
        transaction_hash: from_hex!(transaction_hash),
        transaction_index: Hex.decode_hex_number!(transaction_index)
      }
    end
  end

  @doc """
  Starts a Cartouche.Filter GenServer that polls Ethereum logs matching the
  given filter and forwards parsed events to registered listeners.

  ## Options

    * `:name` — registered name for the GenServer (defaults to `__MODULE__`)
    * `:address` — contract address to filter on (omit to match any)
    * `:topics` — list of topic filters
    * `:events` — list of `ABI.FunctionSelector.t()` or signature strings;
      events are decoded and dispatched as `{:event, {name, params}, log}`
    * `:rpc_opts` — keyword list forwarded to `Cartouche.RPC` calls
    * `:extra_data` — opaque value attached to every log/event message
    * `:check_delay` — milliseconds between filter polls (default 3000)
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    address = Keyword.get(opts, :address)
    topics = Keyword.get(opts, :topics, [])
    events = Keyword.get(opts, :events, [])
    rpc_opts = Keyword.get(opts, :rpc_opts, [])
    extra_data = Keyword.get(opts, :extra_data)
    check_delay = Keyword.get(opts, :check_delay, @check_delay)

    decoders =
      for event <- events, into: %{} do
        function_selector =
          case event do
            %ABI.FunctionSelector{
              types: [%{name: "_topic", type: {:uint, 256}, indexed: true} | rest_types]
            } ->
              %{event | types: rest_types}

            %ABI.FunctionSelector{} ->
              event

            event_abi when is_binary(event_abi) ->
              ABI.FunctionSelector.decode(event_abi)
          end

        {ABI.Event.event_signature(function_selector),
         fn event_topics, event_data ->
           ABI.Event.decode_event(event_data, event_topics, function_selector)
         end}
      end

    all_topics = Enum.map(decoders, fn {topic, _} -> topic end) ++ topics

    GenServer.start_link(
      __MODULE__,
      %{
        address: address,
        topics: all_topics,
        name: name,
        listeners: [],
        decoders: decoders,
        check_delay: check_delay,
        rpc_opts: rpc_opts,
        extra_data: extra_data
      },
      name: name
    )
  end

  @spec set_filter(map()) :: map()
  defp set_filter(%{address: nil, topics: topics, rpc_opts: rpc_opts} = state) do
    {:ok, filter_id} =
      RPC.send_rpc(
        "eth_newFilter",
        [
          %{
            "topics" => Enum.map(topics, &Cartouche.Hex.encode_hex/1)
          }
        ],
        rpc_opts
      )

    Map.put(state, :filter_id, filter_id)
  end

  defp set_filter(%{address: address, topics: topics, rpc_opts: rpc_opts} = state) do
    {:ok, filter_id} =
      RPC.send_rpc(
        "eth_newFilter",
        [
          %{
            "address" => Cartouche.Hex.encode_hex(address),
            "topics" => Enum.map(topics, &Cartouche.Hex.encode_hex/1)
          }
        ],
        rpc_opts
      )

    Map.put(state, :filter_id, filter_id)
  end

  @doc false
  @impl true
  def init(%{check_delay: check_delay} = state) do
    state = set_filter(state)

    Process.send_after(self(), :check_filter, check_delay)

    {:ok, state}
  end

  @doc """
  Registers the calling process as a listener on `filter`. The filter will
  send `{:event, {name, params}, log}` for matched, decoded events and
  `{:log, log}` for every raw log it receives.
  """
  @spec listen(GenServer.server()) :: :ok
  def listen(filter) do
    GenServer.cast(filter, {:listen, self()})
  end

  @doc false
  @impl true
  def handle_cast({:listen, pid}, %{listeners: listeners} = state) do
    {:noreply, Map.put(state, :listeners, [pid | listeners])}
  end

  @doc false
  @impl true
  def handle_info(
        :check_filter,
        %{
          filter_id: filter_id,
          listeners: listeners,
          decoders: decoders,
          name: name,
          check_delay: check_delay,
          rpc_opts: rpc_opts,
          extra_data: extra_data
        } = state
      ) do
    Process.send_after(self(), :check_filter, check_delay)

    state =
      case RPC.send_rpc("eth_getFilterChanges", [filter_id], rpc_opts) do
        {:ok, raw_logs} ->
          {logs, events} =
            raw_logs
            |> Enum.map(&Log.deserialize/1)
            |> Enum.map(fn log -> %{log | extra_data: extra_data} end)
            |> parse_events(decoders)

          for listener <- listeners, {event, log} <- events do
            send(listener, {:event, event, log})
          end

          for listener <- listeners, log <- logs do
            send(listener, {:log, log})
          end

          state

        {:error, %{code: -32_000}} ->
          Logger.error("[Filter #{name}] Filter expired, restarting... Note: some logs may have been lost.")

          set_filter(state)

        {:error, error} ->
          Logger.error("[Filter #{name}] Error getting filter changes: #{inspect(error)}")

          state
      end

    {:noreply, state}
  end

  @spec parse_events([Log.t()], %{binary() => function()}) :: {[Log.t()], [{{atom(), [term()]}, Log.t()}]}
  defp parse_events(logs, decoders) do
    events = do_parse_events(logs, decoders, [])
    {logs, Enum.reverse(events)}
  end

  @spec do_parse_events([Log.t()], %{binary() => function()}, [{{atom(), [term()]}, Log.t()}]) ::
          [{{atom(), [term()]}, Log.t()}]
  defp do_parse_events([], _, events), do: events

  defp do_parse_events([log | rest_logs], decoders, acc_events) do
    [topic_0 | _topic_rest] = log.topics

    case Map.get(decoders, topic_0) do
      nil ->
        do_parse_events(rest_logs, decoders, acc_events)

      decoder_fn ->
        case decoder_fn.(log.topics, log.data) do
          {:ok, event_name, event_params} ->
            do_parse_events(rest_logs, decoders, [{{event_name, event_params}, log} | acc_events])

          {:error, error} ->
            Logger.error("Error decoding log: #{error}")
            do_parse_events(rest_logs, decoders, acc_events)
        end
    end
  end
end

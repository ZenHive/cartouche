defmodule Cartouche.DebugTrace do
  @moduledoc ~S"""
  Represents an Ethereum transaction debug trace, which contains information
  about the call graph of an executed transaction. Note: this is different
  from `trace_call` and instead has deep struct logs for execution.

  See `Cartouche.RPC.debug_trace_call` for getting traces from
  an Ethereum JSON-RPC host.

  See also:
    * QuickNode docs: https://www.quicknode.com/docs/ethereum/debug_traceCall
  """

  use Cartouche.Hex

  defmodule StructLog do
    @moduledoc false
    @type t() :: %__MODULE__{
            depth: integer(),
            gas: integer(),
            gas_cost: integer(),
            op: atom(),
            pc: integer(),
            stack: [binary()]
          }

    defstruct [
      :depth,
      :gas,
      :gas_cost,
      :op,
      :pc,
      :stack
    ]

    @doc ~S"""
    Deserializes a trace's struct-log into a struct.

    ## Examples

        iex> %{
        ...>   "depth" => 1,
        ...>   "gas" => 599978565,
        ...>   "gasCost" => 3,
        ...>   "op" => "PUSH1",
        ...>   "pc" => 2,
        ...>   "stack" => ["0x80"]
        ...> }
        ...> |> Cartouche.DebugTrace.StructLog.deserialize()
        %Cartouche.DebugTrace.StructLog{
          depth: 1,
          gas: 599978565,
          gas_cost: 3,
          op: :PUSH1,
          pc: 2,
          stack: [~h[0x80]]
        }
    """
    @spec deserialize(map()) :: t() | no_return()
    def deserialize(params) do
      %__MODULE__{
        depth: params["depth"],
        gas: params["gas"],
        gas_cost: params["gasCost"],
        op: String.to_atom(params["op"]),
        pc: params["pc"],
        stack: Enum.map(params["stack"], &Cartouche.Hex.decode_hex!/1)
      }
    end

    @doc ~S"""
    Serializes a trace's struct-log into a json map.

    ## Examples

        iex> %Cartouche.DebugTrace.StructLog{
        ...>   depth: 1,
        ...>   gas: 599978565,
        ...>   gas_cost: 3,
        ...>   op: :PUSH1,
        ...>   pc: 2,
        ...>   stack: [~h[0x80]]
        ...> }
        ...> |> Cartouche.DebugTrace.StructLog.serialize()
        %{
          depth: 1,
          gas: 599978565,
          gasCost: 3,
          op: "PUSH1",
          pc: 2,
          stack: ["0x80"]
        }

    """
    @spec serialize(t()) :: map()
    def serialize(struct_log) do
      %{
        depth: struct_log.depth,
        gas: struct_log.gas,
        gasCost: struct_log.gas_cost,
        op: to_string(struct_log.op),
        pc: struct_log.pc,
        stack: Enum.map(struct_log.stack, &Cartouche.Hex.to_hex/1)
      }
    end
  end

  @type t() :: %__MODULE__{
          failed: boolean(),
          gas: integer(),
          return_value: binary(),
          struct_logs: [StructLog.t()]
        }

  defstruct [
    :failed,
    :gas,
    :return_value,
    :struct_logs
  ]

  @doc ~S"""
  Deserializes a trace result from `debug_traceCall`.

  ## Examples

      iex> %{
      ...>   "failed" => false,
      ...>   "gas" => 24034,
      ...>   "returnValue" => "0000000000000000000000000000000000000000000000000858898f93629000",
      ...>   "structLogs" => [
      ...>     %{
      ...>       "depth" => 1,
      ...>       "gas" => 599978568,
      ...>       "gasCost" => 3,
      ...>       "op" => "PUSH1",
      ...>       "pc" => 0,
      ...>       "stack" => []
      ...>     },
      ...>     %{
      ...>       "depth" => 1,
      ...>       "gas" => 599978565,
      ...>       "gasCost" => 3,
      ...>       "op" => "PUSH1",
      ...>       "pc" => 2,
      ...>       "stack" => ["0x80"]
      ...>     },
      ...>     %{
      ...>       "depth" => 1,
      ...>       "gas" => 599978562,
      ...>       "gasCost" => 12,
      ...>       "op" => "MSTORE",
      ...>       "pc" => 4,
      ...>       "stack" => ["0x80", "0x40"]
      ...>     }
      ...>   ]
      ...> }
      ...> |> Cartouche.DebugTrace.deserialize()
      %Cartouche.DebugTrace{
        failed: false,
        gas: 24034,
        return_value: ~h[0x0000000000000000000000000000000000000000000000000858898f93629000],
        struct_logs: [
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978568,
            gas_cost: 3,
            op: :PUSH1,
            pc: 0,
            stack: []
          },
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978565,
            gas_cost: 3,
            op: :PUSH1,
            pc: 2,
            stack: [~h[0x80]]
          },
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978562,
            gas_cost: 12,
            op: :MSTORE,
            pc: 4,
            stack: [~h[0x80], ~h[0x40]]
          }
        ]
      }
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(params) do
    %__MODULE__{
      failed: params["failed"],
      gas: params["gas"],
      return_value: Cartouche.Hex.decode_hex!(params["returnValue"]),
      struct_logs: Enum.map(params["structLogs"], &StructLog.deserialize/1)
    }
  end

  @doc ~S"""
  Serializes a trace result back to a json map.

  ## Examples

      iex> %Cartouche.DebugTrace{
      ...>   failed: false,
      ...>   gas: 24034,
      ...>   return_value: ~h[0x0000000000000000000000000000000000000000000000000858898f93629000],
      ...>   struct_logs: [
      ...>     %Cartouche.DebugTrace.StructLog{
      ...>       depth: 1,
      ...>       gas: 599978568,
      ...>       gas_cost: 3,
      ...>       op: :PUSH1,
      ...>       pc: 0,
      ...>       stack: []
      ...>     },
      ...>     %Cartouche.DebugTrace.StructLog{
      ...>       depth: 1,
      ...>       gas: 599978565,
      ...>       gas_cost: 3,
      ...>       op: :PUSH1,
      ...>       pc: 2,
      ...>       stack: [~h[0x80]]
      ...>     },
      ...>     %Cartouche.DebugTrace.StructLog{
      ...>       depth: 1,
      ...>       gas: 599978562,
      ...>       gas_cost: 12,
      ...>       op: :MSTORE,
      ...>       pc: 4,
      ...>       stack: [~h[0x80], ~h[0x40]]
      ...>     }
      ...>   ]
      ...> }
      ...> |> Cartouche.DebugTrace.serialize()
      %{
        failed: false,
        gas: 24034,
        returnValue: "0000000000000000000000000000000000000000000000000858898f93629000",
        structLogs: [
          %{
            depth: 1,
            gas: 599978568,
            gasCost: 3,
            op: "PUSH1",
            pc: 0,
            stack: []
          },
          %{
            depth: 1,
            gas: 599978565,
            gasCost: 3,
            op: "PUSH1",
            pc: 2,
            stack: ["0x80"]
          },
          %{
            depth: 1,
            gas: 599978562,
            gasCost: 12,
            op: "MSTORE",
            pc: 4,
            stack: ["0x80", "0x40"]
          }
        ]
      }
  """
  @spec serialize(t()) :: map()
  def serialize(debug_trace) do
    %{
      failed: debug_trace.failed,
      gas: debug_trace.gas,
      returnValue: String.replace_prefix(to_hex(debug_trace.return_value), "0x", ""),
      structLogs: Enum.map(debug_trace.struct_logs, &StructLog.serialize/1)
    }
  end
end

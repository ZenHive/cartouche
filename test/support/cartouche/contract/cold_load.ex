defmodule Cartouche.Contract.ColdLoad do
  @moduledoc false
  use Cartouche.Hex

  @cartouche_decode_struct_atoms [:cursor_cold_field, :inner_cold_field]
  @compile {:no_warn_undefined, ABI.FunctionSelector}

  @doc false
  @spec _cartouche_decode_struct_atoms() :: term()
  def _cartouche_decode_struct_atoms do
    @cartouche_decode_struct_atoms
  end

  @doc false
  @spec bytecode() :: term()
  def bytecode do
    hex!("0x00")
  end

  @doc false
  @spec encode_query() :: term()
  def encode_query do
    ABI.encode(query_selector(), [])
  end

  @doc false
  @spec query_selector() :: term()
  def query_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "query",
      returns: [
        %{
          name: "cursorColdField",
          type: {:tuple, [%{name: "innerColdField", type: {:uint, 256}}]}
        }
      ],
      types: []
    }
  end
end

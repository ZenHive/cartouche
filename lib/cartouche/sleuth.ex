defmodule Cartouche.Sleuth do
  @moduledoc ~S"""
  Sleuth allows you to run a contract call as a single
  `eth_call` call.

  Note: Cartouche.Contract.Sleuth generated from `mix cartouche.gen --prefix cartouche/contract ./priv/Sleuth.json`
  """
  use Cartouche.Hex

  alias Cartouche.Contract.Sleuth

  @sleuth_address ~h[0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2]

  @doc """
  Runs a Sleuth contract query: deploys `bytecode` on-chain via `eth_call`
  with `query` calldata and decodes the result against `selector`. Returns
  the decoded values without struct annotations.
  """
  @spec query(binary(), binary(), ABI.FunctionSelector.t(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  def query(bytecode, query, selector, opts \\ []), do: query_internal(bytecode, query, selector, false, opts)

  @doc """
  Same as `query/4`, but tags each decoded value with its ABI type for
  callers that need both type and value (e.g. when re-encoding).
  """
  @spec query_annotated(binary(), binary(), ABI.FunctionSelector.t(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  def query_annotated(bytecode, query, selector, opts \\ []), do: query_internal(bytecode, query, selector, true, opts)

  @doc """
  Convenience wrapper that derives bytecode, query calldata, and selector
  from a generated contract module. Resolves `mod.bytecode/0`,
  `mod.encode_<fun>/0`, and `mod.<fun>_selector/0` and forwards the rest
  to `query/4`.
  """
  @spec query_by(module(), atom() | Keyword.t()) :: {:ok, term()} | {:error, String.t()}
  def query_by(mod, fun) when is_atom(mod) and is_atom(fun), do: query_by(mod, fun, [])
  def query_by(mod, opts) when is_atom(mod) and is_list(opts), do: query_by(mod, :query, opts)

  @doc """
  Single-argument form of `query_by/2`: defaults `fun` to `:query` and
  `opts` to `[]`.
  """
  @spec query_by(module()) :: {:ok, term()} | {:error, String.t()}
  def query_by(mod), do: query_by(mod, :query, [])

  @doc """
  Three-argument form of `query_by/2`: explicit `fun` and `opts`.
  """
  @spec query_by(module(), atom(), Keyword.t()) :: {:ok, term()} | {:error, String.t()}
  def query_by(mod, fun, opts) when is_atom(mod) and is_atom(fun) and is_list(opts) do
    bytecode = try_apply(mod, :bytecode, [])
    # `fun` is a developer-supplied atom (already in the atom table); the derived
    # function names are bounded by the contract module's compile-time API surface.
    query_val = try_apply(mod, String.to_atom("encode_" <> to_string(fun)), [])
    selector = try_apply(mod, String.to_atom(to_string(fun) <> "_selector"), [])

    query_internal(bytecode, query_val, selector, false, opts)
  end

  defp query_internal(bytecode, query, selector, annotated, opts) when is_binary(bytecode) and is_list(opts) do
    {sleuth_address, opts} = Keyword.pop(opts, :sleuth_address, @sleuth_address)
    {decode_binaries, rpc_opts} = Keyword.pop(opts, :decode_binaries, true)

    with {:ok, query_res_bytes} <-
           Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector, false) do
      {:ok,
       postprocess(res, selector.returns,
         annotated: annotated,
         decode_binaries: decode_binaries,
         be_obvious: false
       )}
    end
  end

  @doc """
  Variant of `query/4` that exposes the full set of decode options
  (`:annotated`, `:decode_binaries`, `:decode_structs`, `:named_returns`,
  `:sleuth_address`) as keyword opts. Returns results with named-return
  annotations when configured.
  """
  @spec query_v2(binary(), binary(), ABI.FunctionSelector.t(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  def query_v2(bytecode, query, selector, opts \\ []) do
    {annotated, opts} = Keyword.pop(opts, :annotated, false)
    {sleuth_address, opts} = Keyword.pop(opts, :sleuth_address, @sleuth_address)
    {decode_binaries, opts} = Keyword.pop(opts, :decode_binaries, true)
    {decode_structs, opts} = Keyword.pop(opts, :decode_structs, true)
    {named_returns, rpc_opts} = Keyword.pop(opts, :named_returns, false)

    with {:ok, query_res_bytes} <-
           Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector, decode_structs) do
      {:ok,
       postprocess(res, selector.returns,
         annotated: annotated,
         decode_binaries: decode_binaries,
         named_returns: named_returns,
         be_obvious: true
       )}
    end
  end

  defp try_decode_bytes(bytes) do
    [decoded] = ABI.decode("(bytes)", bytes)
    {:ok, decoded}
  rescue
    e ->
      {:error, "error decoding bytes: #{inspect(e)}"}
  end

  defp try_decode(query_res, selector, decode_structs) do
    if decode_structs, do: preintern_decode_struct_atoms(selector.returns)

    {:ok,
     ABI.decode(
       %ABI.FunctionSelector{types: selector.returns},
       query_res,
       decode_structs: decode_structs
     )}
  rescue
    e ->
      {:error, "error decoding: #{inspect(e)}"}
  end

  defp preintern_decode_struct_atoms(types), do: Enum.each(types, &preintern_type_atoms/1)

  defp preintern_type_atoms(%{name: name, type: type}) do
    preintern_name_atom(name)
    preintern_type_atoms(type)
  end

  defp preintern_type_atoms(_), do: :ok

  # hieroglyph 1.4.0 requires decode_structs field atoms to exist already.
  # Selectors may be built dynamically, so Cartouche owns this bounded pre-intern.
  defp preintern_name_atom(name) when is_binary(name) and name != "" do
    _ = String.to_atom(Macro.underscore(name))
    :ok
  end

  defp preintern_name_atom(_), do: :ok

  # NOTE: decode_structs weirdly also does dynamic return types with named
  # returns, which interacts poorly with our named_returns opt.
  #
  # so we have to take the unordered map, and re-order the values by
  # referencing the ordering of the named_types.
  #
  defp postprocess(results, named_types, opts) when is_map(results) and is_list(named_types) do
    results_values =
      Enum.map(named_types, fn %{name: name} ->
        {_, v} = Enum.find(results, fn {k, _} -> to_string(k) == Macro.underscore(name) end)
        v
      end)

    postprocess(results_values, named_types, opts)
  end

  defp postprocess(results, named_types, opts) when is_list(results) and is_list(named_types) do
    be_obvious = Keyword.get(opts, :be_obvious, false)
    named_returns = Keyword.get(opts, :named_returns, false)

    results
    |> Enum.zip(named_types)
    |> Enum.map(fn {it, t} -> {t.name, postprocess(it, t.type, opts)} end)
    |> then(fn
      processed_results when not be_obvious ->
        case processed_results do
          [] ->
            []

          [{nil, result}] ->
            result

          [{"", result}] ->
            result

          [_more | _than_one] = processed_results ->
            processed_results
            |> Enum.with_index()
            |> Map.new(&with_indexed_name/1)
        end

      processed_results when be_obvious ->
        obvious_results(processed_results, named_returns)
    end)
  end

  defp postprocess(item, {:tuple, named_types}, opts) when is_tuple(item) and is_list(named_types) do
    item
    |> Tuple.to_list()
    |> Enum.zip(named_types)
    |> Map.new(fn {item, %{type: type, name: name}} ->
      {name, postprocess(item, type, opts)}
    end)
  end

  defp postprocess(item, {:tuple, named_types}, opts) when is_map(item) and is_list(named_types) do
    Map.new(item, fn {k, v} ->
      %{type: type} =
        Enum.find(named_types, fn %{name: name} -> Macro.underscore(name) == to_string(k) end)

      {k, postprocess(v, type, opts)}
    end)
  end

  defp postprocess(item, {:array, type}, opts) when is_list(item) do
    Enum.map(item, &postprocess(&1, type, opts))
  end

  defp postprocess(item, {:array, type, _}, opts) when is_list(item), do: postprocess(item, {:array, type}, opts)

  defp postprocess(item, type, opts) do
    item_encoded =
      if Keyword.get(opts, :decode_binaries, true) do
        item
      else
        case type do
          :address -> to_hex(item)
          :bytes -> to_hex(item)
          {:bytes, _size} -> to_hex(item)
          _nonbinary_scalar -> item
        end
      end

    if Keyword.get(opts, :annotated, false) do
      {type, item_encoded}
    else
      item_encoded
    end
  end

  defp try_apply(mod, fun, args) do
    apply(mod, fun, args)
  rescue
    _ ->
      reraise "Sleuth module #{mod} does not define required \"#{fun}/#{Enum.count(args)}\" function",
              __STACKTRACE__
  end

  defp with_indexed_name({{name, it}, i}), do: {fallback_name(name, i), it}

  defp fallback_name(name, i) when is_nil(name) or name == "", do: "var#{i}"
  defp fallback_name(name, _i), do: name

  defp to_named_pair({name, v}), do: {name_keyword(name), v}

  defp name_keyword(name) when is_nil(name) or name == "", do: :__unnamed__
  defp name_keyword(name), do: String.to_atom(Macro.underscore(name))

  defp obvious_results(processed_results, true), do: Enum.map(processed_results, &to_named_pair/1)
  defp obvious_results(processed_results, false), do: Enum.map(processed_results, fn {_, v} -> v end)
end

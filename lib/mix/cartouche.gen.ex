defmodule Mix.Tasks.Cartouche.Gen do
  @shortdoc "Generates wrapper modules from Solidity artifacts or ABI files"

  @moduledoc ~S"""
  `cartouche.gen` generates wrapper modules from Solidity artifacts.

  This module will auto-generate code that can be used to easily call into
  a contract. You can pass in either the ABI output or the full Solidity
  output. If you pass in the Solidity artifacts, you'll get wrappers for
  the bytecode.

  For example, `some_contract.ex`

  ```elixir
  defmodule SomeContract do
    use Cartouche.Hex

    def contract_name do
      "SomeContract"
    end

    def encode_some_function(val) do
      ABI.encode("some_function(uint256)", [val])
    end

    def execute_some_function(contract, val, opts \\ []) do
      Cartouche.RPC.execute_trx(contract, encode_some_function(val), opts)
    end

    def bytecode(), do: ~h[0x...]

    def deployed_bytecode(), do: ~h[0x...]
  end
  ```

  These stubs are useful, since you can easily then call:

  ```iex
  {:ok, tx_id} = Contract.SomeContract.execute_some_function(addr, 55, priority_fee: {55, :gwei})
  ```


  🐉🌊🌊🌊🌊🌊🐉   HERE BE DRAGONS    🐉🌊🌊🌊🌊🌊🐉


  # Usage

  `mix cartouche.gen "out/**/*.json"`

   * `--prefix`: Prefix for the outputed modules
     - E.g. `my_app` -> `MyApp.SomeContract` in `my_app/some_contract.ex`
     - E.g. `my_app/contract` -> `MyApp.Contract.SomeContract` in `my_app/contract/some_contract.ex`
   * `--out`: Out directory, e.g. `lib/my_app/` [default `lib/`]
  """

  use Mix.Task
  use Cartouche.Hex

  require Logger

  defmodule InvalidFileError do
    @moduledoc false
    defexception message: "invalid file error"
  end

  # The contract name isn't obvious from the output-json file, thus we look either by
  # trying to find it in the metadata settings or AST [below]
  @spec get_contract_name_by_metadata(any()) :: any()
  defp get_contract_name_by_metadata(abi) do
    metadata =
      case get_in(abi, ["metadata"]) do
        nil ->
          nil

        m when is_binary(m) ->
          Jason.decode!(m)

        els ->
          els
      end

    case get_in(metadata, ["settings", "compilationTarget"]) do
      nil ->
        nil

      contracts ->
        case Enum.to_list(contracts) do
          [{_k, v} | _rest] ->
            v

          _ ->
            nil
        end
    end
  end

  # Search the AST for the module name from the output-json
  @spec get_contract_name_by_ast(any()) :: any()
  defp get_contract_name_by_ast(abi) do
    %{"sourceUnit" => _, "absolutePath" => absolute_path} = abi["ast"]

    absolute_path
    |> String.split("/")
    |> List.last()
    |> case do
      nil ->
        nil

      file_name ->
        file_name
        |> String.split(".")
        |> List.first()
    end
  end

  # Solidity functions are allowed to overlap with different arugment types, but this
  # would break any Elixir functions, which are not allowed to do that. Thus, we walk
  # the abi from the output-json and see if there are duplicate functions with the
  # same name. If so, we rename any latter by postpending `_aabbccdd` (the function
  # signture) at the end of the function name. The first one doesn't have the prefix,
  # but we could make this more complex to rename all of them if there are any dupes;
  # it would just require two passes.
  @spec rename_dups(any()) :: any()
  defp rename_dups(abis) do
    {abis, _} = Enum.reduce(abis, {[], []}, &accumulate_named_abi/2)
    Enum.reverse(abis)
  end

  @spec accumulate_named_abi(any(), any()) :: any()
  defp accumulate_named_abi(abi, {acc, seen}) do
    fn_sel =
      try do
        ABI.FunctionSelector.parse_specification_item(abi)
      rescue
        e ->
          Logger.warning("Ignoring due to failed parse: #{inspect(abi)}")
          Logger.error(e)

          nil
      end

    case {fn_sel, abi["name"]} do
      {_, nil} -> {[abi | acc], seen}
      {nil, _} -> {[abi | acc], seen}
      {fs, name} -> dedup_named_abi(abi, name, fs, acc, seen)
    end
  end

  @spec dedup_named_abi(map(), String.t(), ABI.FunctionSelector.t(), [map()], [{String.t(), String.t()}]) ::
          {[map()], [{String.t(), String.t()}]}
  defp dedup_named_abi(abi, name, fn_sel, acc, seen) do
    lower_name = String.downcase(name)

    abi_enc_signature = ABI.method_id(fn_sel)
    "0x" <> abi_sig = Cartouche.Hex.encode_hex(abi_enc_signature)
    seen_tuple = {lower_name, abi_sig}

    if Enum.member?(seen, seen_tuple) do
      {acc, seen}
    else
      abi_new = maybe_rename_dup_fn(abi, name, lower_name, abi_sig, seen)
      {[abi_new | acc], [{lower_name, abi_sig} | seen]}
    end
  end

  @spec maybe_rename_dup_fn(any(), any(), any(), any(), any()) :: any()
  defp maybe_rename_dup_fn(abi, name, lower_name, abi_sig, seen) do
    if Enum.member?(Enum.map(seen, fn {n, _} -> n end), lower_name) do
      Map.put(abi, "fn_name", "#{name}_#{abi_sig}")
    else
      abi
    end
  end

  # Function to take the abi from the output-json and output function defs (e.g. encode and execute)
  @spec get_encode_calls(any(), any()) :: any()
  defp get_encode_calls(full_abi, has_bytecode) do
    abi_items = full_abi["abi"] || []
    renamed_abis = rename_dups(abi_items)
    has_errors = Enum.any?(renamed_abis, &(&1["type"] == "error"))

    {fns, decoders, events, errors} =
      Enum.reduce(renamed_abis, {[], [], [], []}, fn abi, acc ->
        merge_encode_call_result(acc, get_encode_call(abi, has_bytecode, has_errors))
      end)

    decoders = [
      quote do
        def decode_call(_), do: :not_found
      end
      | decoders
    ]

    errors = [
      quote do
        def decode_error(_), do: :not_found
      end
      | errors
    ]

    events = [
      quote do
        def decode_event(_, _), do: :not_found
      end
      | events
    ]

    fns ++ Enum.reverse(decoders, Enum.reverse(events, Enum.reverse(errors)))
  end

  @spec merge_encode_call_result(any(), any()) :: any()
  defp merge_encode_call_result({acc_fns, acc_decoders, acc_events, acc_errors}, result) do
    case result do
      {functions, generic_call_decoder, nil, nil} ->
        {acc_fns ++ functions, [generic_call_decoder | acc_decoders], acc_events, acc_errors}

      {functions, nil, generic_event_fn, nil} ->
        {acc_fns ++ functions, acc_decoders, [generic_event_fn | acc_events], acc_errors}

      {functions, nil, nil, generic_error_fn} ->
        {acc_fns ++ functions, acc_decoders, acc_events, [generic_error_fn | acc_errors]}

      nil ->
        {acc_fns, acc_decoders, acc_events, acc_errors}
    end
  end

  # Parses the ABI spec and generates the functions (encode and execute) if we can parse
  # the ABI spec. We've recently updated our ABI parsing library that this doesn't fail
  # nearly as often as it used to (e.g. it can handle tuples)
  @spec get_encode_call(any(), any(), any()) :: any()
  defp get_encode_call(abi, has_bytecode, has_errors) do
    fn_selector =
      try do
        ABI.FunctionSelector.parse_specification_item(abi)
      rescue
        _e ->
          Logger.warning("Ignoring due to failed parse: #{inspect(abi)}")
          nil
      end

    case fn_selector do
      %ABI.FunctionSelector{function: name} = fs when not is_nil(name) ->
        encode_function_call(fs, abi["fn_name"] || name, has_bytecode, has_errors)

      %ABI.FunctionSelector{function_type: function_type} = fs ->
        encode_function_call(fs, to_string(function_type), has_bytecode, has_errors)

      _ ->
        Logger.warning("Ignoring function due to missing name")
        nil
    end
  end

  # Generate the encode and execute functions. This is ... complex (read: hacky)
  @spec encode_function_call(any(), any(), any(), any()) :: any()
  defp encode_function_call(selector, fn_name, has_bytecode, has_errors) do
    names = function_names(fn_name)
    argument_types = derive_argument_types(selector)
    {execute_arguments, encode_arguments, execute_values, encode_values} = build_argument_specs(argument_types)
    sig = signature_data(selector)

    if abort?(execute_arguments, selector, has_bytecode) do
      Logger.warning("Ignoring function #{selector.function} due to unknown argument")
      nil
    else
      ctx = %{
        names: names,
        execute_arguments: execute_arguments,
        encode_arguments: encode_arguments,
        execute_values: execute_values,
        encode_values: encode_values,
        sig: sig,
        selector: selector,
        has_errors: has_errors
      }

      select_emitted_fns(selector, has_bytecode, build_function_quotes(ctx))
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec function_names(any()) :: any()
  defp function_names(fn_name) do
    underscored = Macro.underscore(fn_name)

    %{
      encode: String.to_atom("encode_#{underscored}"),
      encode_event: String.to_atom("encode_#{underscored}_event"),
      build_trx: String.to_atom("build_trx_#{underscored}"),
      call: String.to_atom("call_#{underscored}"),
      estimate_gas: String.to_atom("estimate_gas_#{underscored}"),
      execute: String.to_atom("execute_#{underscored}"),
      prepare: String.to_atom("prepare_#{underscored}"),
      selector: String.to_atom("#{underscored}_selector"),
      event_selector: String.to_atom("#{underscored}_event_selector"),
      decode_event: String.to_atom("decode_#{underscored}_event"),
      decode_error: String.to_atom("decode_#{underscored}_error"),
      decode_call: String.to_atom("decode_#{underscored}_call"),
      exec_vm: String.to_atom("exec_vm_#{underscored}"),
      exec_vm_raw: String.to_atom("exec_vm_#{underscored}_raw")
    }
  end

  @spec derive_argument_types(any()) :: any()
  defp derive_argument_types(%{function_type: t}) when t in [:fallback, :receive] do
    [%{type: :bytes, name: "data"}]
  end

  defp derive_argument_types(selector), do: selector.types

  # We are returning 4 values and will do a double unzip here so we can return
  # them from one function but get 4 separate lists.
  @spec build_argument_specs(any()) :: any()
  defp build_argument_specs(argument_types) do
    {args, vals} =
      argument_types
      |> Enum.with_index(&build_argument_spec/2)
      |> Enum.unzip()

    {execute_arguments, encode_arguments} = Enum.unzip(args)
    {execute_values, encode_values} = Enum.unzip(vals)
    {execute_arguments, encode_arguments, execute_values, encode_values}
  end

  @spec build_argument_spec(any(), any()) :: any()
  defp build_argument_spec(argument_type, index) do
    if Map.has_key?(argument_type, :name) do
      name = arg_name(argument_type, index)
      names = tuple_field_names(argument_type.type)

      if struct_argument?(names) do
        build_struct_argument_spec(name, names)
      else
        build_simple_argument_spec(name)
      end
    else
      {{nil, nil}, {nil, nil}}
    end
  end

  @spec arg_name(any(), any()) :: any()
  defp arg_name(argument_type, index) do
    case Map.get(argument_type, :name) do
      x when is_nil(x) or x == "" -> "var#{index}"
      els -> String.trim_leading(els, "_")
    end
  end

  @spec tuple_field_names(any()) :: any()
  defp tuple_field_names({:tuple, tuple_types}), do: Enum.map(tuple_types, &Map.get(&1, :name))
  defp tuple_field_names(_), do: [nil]

  @spec struct_argument?(any()) :: any()
  defp struct_argument?(names) do
    not Enum.member?(names, nil) and not Enum.member?(names, "")
  end

  # For a struct, we make the arguments a map keyed by field name. We need to
  # pass them as a `{tuple}` to the encode function (positional), and we need
  # to underscore unused vars to silence compiler warnings.
  #
  # HERE BE DRAGONS 🐉🌊🌊🌊🌊🌊🐉
  # sobelow_skip ["DOS.StringToAtom"]
  @spec build_struct_argument_spec(any(), any()) :: any()
  defp build_struct_argument_spec(name, names) do
    name_var = Macro.var(String.to_atom(Macro.underscore(name)), __MODULE__)
    encode_unused_name_var = Macro.var(String.to_atom("_" <> Macro.underscore(name)), __MODULE__)

    encode_els = Enum.map(names, &name_value_pair/1)
    execute_els_unused = Enum.map(names, &unused_name_value_pair/1)
    encode_value_inners = Enum.map(names, &positional_value/1)

    encode_argument =
      quote do
        unquote(encode_unused_name_var) = %{unquote_splicing(encode_els)}
      end

    execute_argument =
      quote do
        unquote(name_var) = %{unquote_splicing(execute_els_unused)}
      end

    encode_value =
      quote do
        {unquote_splicing(encode_value_inners)}
      end

    {{execute_argument, encode_argument}, {name_var, encode_value}}
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec build_simple_argument_spec(any()) :: any()
  defp build_simple_argument_spec(name) do
    var = Macro.var(String.to_atom(Macro.underscore(name)), __MODULE__)
    {{var, var}, {var, var}}
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec name_value_pair(any()) :: any()
  defp name_value_pair(el) do
    el_atom = String.to_atom(Macro.underscore(el))
    el_var = Macro.var(el_atom, __MODULE__)

    quote do
      {unquote(el_atom), unquote(el_var)}
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec unused_name_value_pair(any()) :: any()
  defp unused_name_value_pair(el) do
    el_atom = String.to_atom(Macro.underscore(el))
    el_atom_unused = String.to_atom("_" <> Macro.underscore(el))
    el_var_unused = Macro.var(el_atom_unused, __MODULE__)

    quote do
      {unquote(el_atom), unquote(el_var_unused)}
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec positional_value(any()) :: any()
  defp positional_value(el) do
    el_atom = String.to_atom(Macro.underscore(el))
    el_var = Macro.var(el_atom, __MODULE__)

    quote do
      unquote(el_var)
    end
  end

  @spec signature_data(ABI.FunctionSelector.t()) :: %{
          abi: binary(),
          abi_enc_signature_list: [byte()],
          abi_enc_signature_hex: Macro.t(),
          signature_list: [byte()],
          error_name: String.t() | nil
        }
  defp signature_data(selector) do
    abi = ABI.FunctionSelector.encode(selector)
    abi_enc_signature = ABI.method_id(selector)

    signature = Cartouche.Hash.keccak(abi)

    abi_enc_signature_list = :erlang.binary_to_list(abi_enc_signature)
    abi_enc_signature_hex_base = Cartouche.Hex.encode_hex(abi_enc_signature)

    abi_enc_signature_hex =
      quote do
        _signature = hex!(unquote(abi_enc_signature_hex_base))
      end

    %{
      abi: abi,
      abi_enc_signature_list: abi_enc_signature_list,
      abi_enc_signature_hex: abi_enc_signature_hex,
      signature_list: :erlang.binary_to_list(signature),
      error_name: selector.function
    }
  end

  @spec abort?(any(), any(), any()) :: any()
  defp abort?(execute_arguments, selector, has_bytecode) do
    Enum.member?(execute_arguments, nil) or
      (selector.function_type == :constructor and not has_bytecode)
  end

  @spec build_function_quotes(any()) :: any()
  defp build_function_quotes(ctx) do
    %{
      encode_fn: build_encode_fn(ctx),
      prepare_fn: build_prepare_fn(ctx),
      build_trx_fn: build_build_trx_fn(ctx),
      call_fn: build_call_fn(ctx),
      estimate_gas_fn: build_estimate_gas_fn(ctx),
      execute_fn: build_execute_fn(ctx),
      exec_vm_fn: build_exec_vm_fn(ctx),
      exec_vm_raw_fn: build_exec_vm_raw_fn(ctx),
      selector_fn: build_selector_fn(ctx),
      event_selector_fn: build_event_selector_fn(ctx),
      decode_event_fn: build_decode_event_fn(ctx),
      decode_call_fn: build_decode_call_fn(ctx),
      decode_error_fn: build_decode_error_fn(ctx),
      generic_decode_call_fn: build_generic_decode_call_fn(ctx),
      generic_error_fn: build_generic_error_fn(ctx),
      generic_event_fn: build_generic_event_fn(ctx)
    }
  end

  @spec build_encode_fn(any()) :: any()
  defp build_encode_fn(%{selector: %{function_type: :constructor}} = ctx) do
    %{names: names, encode_arguments: encode_arguments, encode_values: encode_values, sig: sig} = ctx

    quote do
      def unquote(names.encode)(unquote_splicing(encode_arguments)) do
        bytecode() <> ABI.encode(unquote(sig.abi), [{unquote_splicing(encode_values)}])
      end
    end
  end

  defp build_encode_fn(%{selector: %{function_type: t}} = ctx) when t in [:fallback, :receive] do
    %{names: names, encode_arguments: encode_arguments} = ctx

    quote do
      def unquote(names.encode)(unquote_splicing(encode_arguments)) do
        (unquote_splicing(encode_arguments))
      end
    end
  end

  defp build_encode_fn(%{selector: %{function_type: :event}} = ctx) do
    %{names: names, encode_arguments: encode_arguments, encode_values: encode_values} = ctx

    quote do
      def unquote(names.encode_event)(unquote_splicing(encode_arguments)) do
        ABI.encode(unquote(names.event_selector)(), unquote(encode_values))
      end
    end
  end

  defp build_encode_fn(ctx) do
    %{names: names, encode_arguments: encode_arguments, encode_values: encode_values} = ctx

    quote do
      def unquote(names.encode)(unquote_splicing(encode_arguments)) do
        ABI.encode(unquote(names.selector)(), unquote(encode_values))
      end
    end
  end

  @spec build_prepare_fn(any()) :: any()
  defp build_prepare_fn(%{selector: %{function_type: :constructor}} = ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.prepare)(unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.prepare_trx(
          <<0::256>>,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_prepare_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.prepare)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.prepare_trx(
          contract,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  @spec build_build_trx_fn(any()) :: any()
  defp build_build_trx_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.build_trx)(contract, unquote_splicing(execute_arguments)) do
        %Call{
          destination: contract,
          data: unquote(names.encode)(unquote_splicing(execute_values))
        }
      end
    end
  end

  @spec build_call_fn(any()) :: any()
  defp build_call_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.call)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.call_trx(
          unquote(names.build_trx)(contract, unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  @spec build_estimate_gas_fn(any()) :: any()
  defp build_estimate_gas_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.estimate_gas)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.estimate_gas(
          unquote(names.build_trx)(contract, unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  @spec build_execute_fn(any()) :: any()
  defp build_execute_fn(%{selector: %{function_type: :constructor}} = ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.execute)(unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.execute_trx(
          <<0::256>>,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_execute_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.execute)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.execute_trx(
          contract,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  @spec build_exec_vm_fn(any()) :: any()
  defp build_exec_vm_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.exec_vm)(unquote_splicing(execute_arguments), exec_opts \\ []) do
        case Cartouche.VM.exec_call(
               deployed_bytecode(),
               unquote(names.encode)(unquote_splicing(execute_values)),
               exec_opts
             ) do
          {:ok, return_data} ->
            preintern_return_atoms!(unquote(names.selector)().returns)

            case ABI.decode(
                   %ABI.FunctionSelector{types: unquote(names.selector)().returns},
                   return_data,
                   decode_structs: true
                 ) do
              m when is_map(m) -> {:ok, m}
              [decoded] -> {:ok, decoded}
              els -> {:ok, els}
            end

          {:revert, revert_data} ->
            case apply(__MODULE__, :decode_error, [revert_data]) do
              {:ok, error, data} -> {:revert, error, data}
              :not_found -> {:revert, "Unknown", revert_data}
            end
        end
      end
    end
  end

  @spec build_preintern_return_atoms_fns() :: [Macro.t()]
  defp build_preintern_return_atoms_fns do
    [
      build_preintern_return_atoms_list_fn(),
      build_preintern_return_atoms_fallback_fn(),
      build_preintern_return_atom_named_fn(),
      build_preintern_return_atom_fallback_fn(),
      build_preintern_tuple_atoms_fn(),
      build_preintern_array_atoms_fn(),
      build_preintern_fixed_array_atoms_fn(),
      build_preintern_type_atoms_fallback_fn(),
      build_preintern_name_atom_fn(),
      build_preintern_name_atom_fallback_fn()
    ]
  end

  @spec build_preintern_return_atoms_list_fn() :: Macro.t()
  defp build_preintern_return_atoms_list_fn do
    quote do
      defp preintern_return_atoms!(types) when is_list(types) do
        Enum.each(types, &preintern_return_atom!/1)
      end
    end
  end

  @spec build_preintern_return_atoms_fallback_fn() :: Macro.t()
  defp build_preintern_return_atoms_fallback_fn do
    quote do
      defp preintern_return_atoms!(_), do: :ok
    end
  end

  @spec build_preintern_return_atom_named_fn() :: Macro.t()
  defp build_preintern_return_atom_named_fn do
    quote do
      # `decode_structs: true` in hieroglyph 1.4+ requires these atoms to exist
      # before decode. Generated modules own the bounded ABI field set, so this
      # compile-time wrapper is the right place to intern those atoms explicitly.
      defp preintern_return_atom!(%{name: name, type: type}) do
        preintern_name_atom!(name)
        preintern_type_atoms!(type)
      end
    end
  end

  @spec build_preintern_return_atom_fallback_fn() :: Macro.t()
  defp build_preintern_return_atom_fallback_fn do
    quote do
      defp preintern_return_atom!(_), do: :ok
    end
  end

  @spec build_preintern_tuple_atoms_fn() :: Macro.t()
  defp build_preintern_tuple_atoms_fn do
    quote do
      defp preintern_type_atoms!({:tuple, types}), do: preintern_return_atoms!(types)
    end
  end

  @spec build_preintern_array_atoms_fn() :: Macro.t()
  defp build_preintern_array_atoms_fn do
    quote do
      defp preintern_type_atoms!({:array, type}), do: preintern_type_atoms!(type)
    end
  end

  @spec build_preintern_fixed_array_atoms_fn() :: Macro.t()
  defp build_preintern_fixed_array_atoms_fn do
    quote do
      defp preintern_type_atoms!({:array, type, _size}), do: preintern_type_atoms!(type)
    end
  end

  @spec build_preintern_type_atoms_fallback_fn() :: Macro.t()
  defp build_preintern_type_atoms_fallback_fn do
    quote do
      defp preintern_type_atoms!(_), do: :ok
    end
  end

  @spec build_preintern_name_atom_fn() :: Macro.t()
  defp build_preintern_name_atom_fn do
    quote do
      defp preintern_name_atom!(name) when is_binary(name) and name != "" do
        name
        |> Macro.underscore()
        |> String.to_atom()
      end
    end
  end

  @spec build_preintern_name_atom_fallback_fn() :: Macro.t()
  defp build_preintern_name_atom_fallback_fn do
    quote do
      defp preintern_name_atom!(_), do: :ok
    end
  end

  @spec build_exec_vm_raw_fn(any()) :: any()
  defp build_exec_vm_raw_fn(ctx) do
    %{names: names, execute_arguments: execute_arguments, execute_values: execute_values} = ctx

    quote do
      def unquote(names.exec_vm_raw)(unquote_splicing(execute_arguments), exec_opts \\ []) do
        Cartouche.VM.exec_call(
          deployed_bytecode(),
          unquote(names.encode)(unquote_splicing(execute_values)),
          exec_opts
        )
      end
    end
  end

  @spec build_selector_fn(any()) :: any()
  defp build_selector_fn(%{names: names, selector: selector}) do
    quote do
      def unquote(names.selector)() do
        unquote(Macro.escape(selector))
      end
    end
  end

  @spec build_event_selector_fn(any()) :: any()
  defp build_event_selector_fn(%{names: names, selector: selector}) do
    quote do
      def unquote(names.event_selector)() do
        unquote(Macro.escape(selector))
      end
    end
  end

  @spec build_decode_event_fn(any()) :: any()
  defp build_decode_event_fn(%{names: names, sig: sig}) do
    quote do
      def unquote(names.decode_event)(topics, data) when is_list(topics) do
        unquote(sig.abi_enc_signature_hex)
        ABI.Event.decode_event(data, topics, unquote(names.event_selector)())
      end
    end
  end

  @spec build_decode_call_fn(any()) :: any()
  defp build_decode_call_fn(%{names: names, sig: sig}) do
    quote do
      def unquote(names.decode_call)(<<unquote_splicing(sig.abi_enc_signature_list)>> <> calldata) do
        unquote(sig.abi_enc_signature_hex)
        ABI.decode(unquote(names.selector)(), calldata)
      end
    end
  end

  @spec build_decode_error_fn(any()) :: any()
  defp build_decode_error_fn(%{names: names, sig: sig}) do
    quote do
      def unquote(names.decode_error)(<<unquote_splicing(sig.abi_enc_signature_list)>> <> error) do
        unquote(sig.abi_enc_signature_hex)
        ABI.decode(unquote(names.selector)(), error)
      end
    end
  end

  @spec build_generic_decode_call_fn(any()) :: any()
  defp build_generic_decode_call_fn(%{names: names, sig: sig}) do
    quote do
      def decode_call(<<unquote_splicing(sig.abi_enc_signature_list)>> <> _ = calldata) do
        unquote(sig.abi_enc_signature_hex)
        {:ok, unquote(sig.error_name), unquote(names.decode_call)(calldata)}
      end
    end
  end

  @spec build_generic_error_fn(any()) :: any()
  defp build_generic_error_fn(%{names: names, sig: sig}) do
    quote do
      def decode_error(<<unquote_splicing(sig.abi_enc_signature_list)>> <> _ = error) do
        unquote(sig.abi_enc_signature_hex)
        {:ok, unquote(sig.error_name), unquote(names.decode_error)(error)}
      end
    end
  end

  @spec build_generic_event_fn(any()) :: any()
  defp build_generic_event_fn(%{names: names, sig: sig}) do
    quote do
      def decode_event([<<unquote_splicing(sig.signature_list)>> | _] = topics, data) do
        unquote(names.decode_event)(topics, data)
      end
    end
  end

  @spec select_emitted_fns(any(), any(), any()) :: any()
  defp select_emitted_fns(%{function_type: :error}, _has_bytecode, fns) do
    {[fns.selector_fn, fns.encode_fn, fns.decode_error_fn], nil, nil, fns.generic_error_fn}
  end

  defp select_emitted_fns(%{function_type: :event}, _has_bytecode, fns) do
    {[fns.event_selector_fn, fns.encode_fn, fns.decode_event_fn], nil, fns.generic_event_fn, nil}
  end

  defp select_emitted_fns(%{function_type: t}, _has_bytecode, fns) when t in [:constructor, :fallback, :receive] do
    {[fns.encode_fn, fns.prepare_fn, fns.execute_fn], nil, nil, nil}
  end

  defp select_emitted_fns(%{state_mutability: :pure}, true, fns) do
    {[
       fns.selector_fn,
       fns.encode_fn,
       fns.prepare_fn,
       fns.build_trx_fn,
       fns.call_fn,
       fns.estimate_gas_fn,
       fns.execute_fn,
       fns.decode_call_fn,
       fns.exec_vm_fn,
       fns.exec_vm_raw_fn
     ], fns.generic_decode_call_fn, nil, nil}
  end

  defp select_emitted_fns(_selector, _has_bytecode, fns) do
    {[
       fns.selector_fn,
       fns.encode_fn,
       fns.prepare_fn,
       fns.build_trx_fn,
       fns.call_fn,
       fns.estimate_gas_fn,
       fns.execute_fn,
       fns.decode_call_fn
     ], fns.generic_decode_call_fn, nil, nil}
  end

  # Generate the bytecode function
  # Note: I wanted to use ~h[] syntax, but generating that was being weird.
  @spec get_bytecode(any()) :: any()
  defp get_bytecode(abi) do
    bytecode = get_in(abi, ["bytecode", "object"]) || get_in(abi, ["bin"])

    if blank_bytecode?(bytecode) do
      []
    else
      [
        quote do
          def bytecode, do: hex!(unquote(bytecode))
        end
      ]
    end
  end

  # Generate the deployed bytecode function
  @spec get_deployed_bytecode(any()) :: any()
  defp get_deployed_bytecode(abi) do
    deployed_bytecode =
      get_in(abi, ["deployedBytecode", "object"]) || get_in(abi, ["bin-runtime"])

    if blank_bytecode?(deployed_bytecode) do
      []
    else
      [
        quote do
          def deployed_bytecode, do: hex!(unquote(deployed_bytecode))
        end
      ]
    end
  end

  # Treat nil, empty/whitespace strings, and "0x"/"0x"+whitespace as missing
  # bytecode. Foundry emits "0x" for interfaces with no on-chain bytecode
  # (e.g. Hardhat's IConsole), and `is_nil` alone wouldn't catch those —
  # leaving callers to compile-encode <<>> as if it were real code.
  @spec blank_bytecode?(any()) :: any()
  defp blank_bytecode?(nil), do: true

  defp blank_bytecode?(s) when is_binary(s) do
    case String.trim(s) do
      "" -> true
      "0x" -> true
      "0x" <> rest -> String.trim(rest) == ""
      _ -> false
    end
  end

  defp blank_bytecode?(_), do: false

  # The crux of it. Builds the entire module with function declarations, etc
  # based on the output-json "abi" of a given Solidity contract.
  @spec build_module(any(), any(), any()) :: any()
  defp build_module(prefix, out, abi_map) do
    contract_name = get_contract_name_by_metadata(abi_map) || get_contract_name_by_ast(abi_map)
    if is_nil(contract_name), do: raise("did not find contract name")

    prefix_parts =
      prefix
      |> String.split("/")
      |> Enum.filter(fn x -> String.length(x) > 0 end)

    prefix_mod = Enum.map(prefix_parts, &Macro.camelize/1)

    module_name =
      String.to_atom(Enum.join(List.flatten(["Elixir", prefix_mod, contract_name]), "."))

    file_name =
      Path.join(
        List.flatten([
          out,
          prefix_parts,
          "#{Macro.underscore(contract_name)}.ex"
        ])
      )

    bytecode_decl = get_bytecode(abi_map)
    deployed_bytecode_decl = get_deployed_bytecode(abi_map)
    encode_call_decl = get_encode_calls(abi_map, not Enum.empty?(bytecode_decl))

    preintern_return_atoms_decl =
      if uses_preintern_return_atoms?(encode_call_decl) do
        build_preintern_return_atoms_fns()
      else
        []
      end

    quote_result =
      quote do
        defmodule unquote(module_name) do
          @moduledoc false
          use Cartouche.Hex

          alias Cartouche.Transaction.Call

          def contract_name, do: unquote(contract_name)

          unquote_splicing(encode_call_decl)
          unquote_splicing(bytecode_decl)
          unquote_splicing(deployed_bytecode_decl)
          unquote_splicing(preintern_return_atoms_decl)
        end
      end

    contents =
      quote_result
      |> annotate_internal_defs()
      |> Macro.to_string()
      |> strip_zero_arity_def_parens()

    {file_name, contents}
  end

  @spec uses_preintern_return_atoms?(Macro.t() | [Macro.t()]) :: boolean()
  defp uses_preintern_return_atoms?(quoted) do
    {_quoted, used?} =
      Macro.prewalk(quoted, false, fn
        {:preintern_return_atoms!, _, _} = node, _used? -> {node, true}
        node, used? -> {node, used?}
      end)

    used?
  end

  # Macro-time `def unquote(name)()` requires the trailing parens for the AST to
  # form a valid function-name shape, but the formatted output then trips
  # Credo's ParenthesesOnZeroArityDefs. Strip empty parens from `def`/`defp`
  # lines as a post-process — text-level only, def-line-anchored.
  @spec strip_zero_arity_def_parens(any()) :: any()
  defp strip_zero_arity_def_parens(source) do
    Regex.replace(~r/^(\s*defp?\s+[a-z_][a-zA-Z0-9_!?]*)\(\)/m, source, "\\1")
  end

  # Generated fixture modules are internal test infrastructure (`@moduledoc false`).
  # Per the project convention `docs on public surface, @doc false on internal`,
  # every emitted public function gets `@doc false` + a permissive `@spec`. The
  # spec uses `term()` for all argument and return positions because the generator
  # has no insight into the contract's domain types — Doctor's spec-coverage gate
  # is satisfied by *presence* of a spec, not type fidelity. Multi-clause
  # functions get one annotation pair before the first clause only (subsequent
  # clauses are skipped via the seen-set; duplicate `@spec` for a given arity
  # is a compile error).
  #
  # Task 50 will replace `term()` placeholders with ABI-derived Elixir types and
  # emit the max-line-length pragma conditionally when bytestring topic-0 hashes
  # overflow 120 chars after `mix format`.
  @spec annotate_internal_defs(any()) :: any()
  defp annotate_internal_defs({:defmodule, dm_meta, [name, [do: do_block]]}) do
    {:defmodule, dm_meta, [name, [do: annotate_block(do_block)]]}
  end

  @spec annotate_block(any()) :: any()
  defp annotate_block({:__block__, b_meta, stmts}) do
    {new_stmts, _seen} = Enum.flat_map_reduce(stmts, MapSet.new(), &annotate_stmt/2)
    {:__block__, b_meta, new_stmts}
  end

  defp annotate_block(single_stmt) do
    {stmts, _seen} = annotate_stmt(single_stmt, MapSet.new())

    case stmts do
      [single] -> single
      many -> {:__block__, [], many}
    end
  end

  @spec annotate_stmt(any(), any()) :: any()
  defp annotate_stmt({kind, _, [head, _body]} = def_ast, seen) when kind in [:def, :defp] do
    case extract_name_arity(head) do
      nil ->
        {[def_ast], seen}

      key ->
        if MapSet.member?(seen, key) do
          {[def_ast], seen}
        else
          {name, arity} = key
          {build_annotations(kind, name, arity) ++ [def_ast], MapSet.put(seen, key)}
        end
    end
  end

  defp annotate_stmt({:alias, _, _} = alias_ast, seen), do: {[alias_ast], seen}

  defp annotate_stmt(other, seen), do: {[other], seen}

  @spec extract_name_arity(any()) :: any()
  defp extract_name_arity({:when, _, [inner, _guard]}), do: extract_name_arity(inner)
  defp extract_name_arity({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp extract_name_arity({name, _, _ctx}) when is_atom(name), do: {name, 0}
  defp extract_name_arity(_), do: nil

  @spec build_annotations(any(), any(), any()) :: any()
  defp build_annotations(kind, name, arity) do
    spec_args = List.duplicate({:term, [], []}, arity)
    spec_call = {name, [], spec_args}
    spec_ret = {:term, [], []}

    doc_annotation =
      if kind == :def do
        [{:@, [], [{:doc, [], [false]}]}]
      else
        []
      end

    doc_annotation ++ [{:@, [], [{:spec, [], [{:"::", [], [spec_call, spec_ret]}]}]}]
  end

  # Gets the output-json of all included Solidity files to auto-generate.
  @spec get_json_out(any()) :: any()
  defp get_json_out(patterns) do
    patterns
    |> Enum.map(fn pattern -> Path.wildcard(pattern) end)
    |> List.flatten()
    |> Enum.map(fn filename -> {filename, File.read!(filename)} end)
    |> Enum.map(fn {filename, contents} -> {filename, Jason.decode!(contents)} end)
    |> Enum.map(fn {filename, contents} ->
      cond do
        is_map(contents) and Map.has_key?(contents, "abi") ->
          # Normal Soidity output
          contents

        is_list(contents) ->
          # Just an ABI, convert to Solidity
          %{
            "abi" => contents,
            "metadata" => %{
              "settings" => %{
                "compilationTarget" => %{
                  filename => Macro.camelize(Path.basename(filename, ".json"))
                }
              }
            }
          }

        true ->
          raise InvalidFileError, "Invalid Solidity output or ABI in `#{filename}`"
      end
    end)
  end

  @doc false
  @spec run(any()) :: any()
  def run(args) do
    case OptionParser.parse(args, strict: [prefix: :string, out: :string]) do
      {opts, [_ | _] = patterns, []} ->
        prefix = Keyword.get(opts, :prefix, "")
        out = Keyword.get(opts, :out, "lib/")

        patterns
        |> get_json_out()
        |> Enum.map(fn abi_map -> build_module(prefix, out, abi_map) end)
        |> Enum.each(fn {path, contents} ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, Code.format_string!(contents) ++ "\n")
          Logger.info("Generated #{path}")
        end)

      _ ->
        raise "usage: mix cartouche.gen --prefix [prefix] --out [out=lib/] [patterns]"
    end
  end
end

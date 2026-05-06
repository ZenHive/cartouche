defmodule Mix.Tasks.Cartouche.GenTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Mix.Tasks.Cartouche.Gen

  # Drives the generator end-to-end through its public Mix-task entrypoint
  # so the assertions cover the full code path users actually hit.

  setup do
    tmp = Path.join(System.tmp_dir!(), "cartouche_gen_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp pure_function_abi do
    [
      %{
        "type" => "function",
        "name" => "ping",
        "inputs" => [%{"name" => "x", "type" => "uint256", "internalType" => "uint256"}],
        "outputs" => [%{"name" => "", "type" => "uint256", "internalType" => "uint256"}],
        "stateMutability" => "pure"
      }
    ]
  end

  defp synthetic_abi do
    __DIR__
    |> Path.join("../support/synthetic_abi.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp write_artifact(tmp, name, bytecode_object, abi, opts) do
    artifact = %{
      "abi" => abi,
      "metadata" => metadata_for(name, opts)
    }

    write_artifact_map(tmp, name, put_bytecode(artifact, bytecode_object))
  end

  defp write_artifact_map(tmp, name, artifact) do
    path = Path.join(tmp, "#{name}.json")
    File.write!(path, Jason.encode!(artifact))
    path
  end

  defp metadata_for(name, opts) do
    if Keyword.get(opts, :metadata, true) do
      %{"settings" => %{"compilationTarget" => %{"src/#{name}.sol" => name}}}
    end
  end

  defp put_bytecode(artifact, bytecode_object) do
    case bytecode_object do
      :absent ->
        artifact

      v ->
        bytecode = %{"object" => v}

        artifact
        |> Map.put("bytecode", bytecode)
        |> Map.put("deployedBytecode", bytecode)
    end
  end

  defp put_bytecodes(artifact, init_bytecode, deployed_bytecode) do
    artifact
    |> maybe_put_bytecode("bytecode", init_bytecode)
    |> maybe_put_bytecode("deployedBytecode", deployed_bytecode)
  end

  defp maybe_put_bytecode(artifact, _key, :absent), do: artifact
  defp maybe_put_bytecode(artifact, key, bytecode), do: Map.put(artifact, key, %{"object" => bytecode})

  defp generate(tmp, name, bytecode_object, abi \\ pure_function_abi(), opts \\ []) do
    artifact_path = write_artifact(tmp, name, bytecode_object, abi, opts)
    generate_file(tmp, name, artifact_path)
  end

  defp generate_artifact(tmp, name, artifact) do
    artifact_path = write_artifact_map(tmp, name, artifact)
    generate_file(tmp, name, artifact_path)
  end

  defp generate_file(tmp, name, artifact_path) do
    out_dir = Path.join(tmp, "out")
    File.mkdir_p!(out_dir)

    Gen.run([
      "--prefix",
      "gen_test",
      "--out",
      out_dir,
      artifact_path
    ])

    out_dir
    |> Path.join("gen_test")
    |> Path.join("#{Macro.underscore(name)}.ex")
    |> File.read!()
  end

  defp solidity_artifact(name, abi, opts \\ []) do
    metadata =
      %{
        "settings" => %{
          "compilationTarget" => %{"src/#{name}.sol" => name}
        }
      }

    metadata =
      if Keyword.get(opts, :metadata_json?, false) do
        Jason.encode!(metadata)
      else
        metadata
      end

    %{"abi" => abi, "metadata" => metadata}
  end

  defp ast_artifact(name, abi) do
    %{
      "abi" => abi,
      "ast" => %{
        "sourceUnit" => 1,
        "absolutePath" => "/synthetic/contracts/#{name}.sol"
      }
    }
  end

  defp abi_only_file(tmp, name, abi) do
    path = Path.join(tmp, "#{name}.json")
    File.write!(path, Jason.encode!(abi))
    path
  end

  defp generate_abi_file(tmp, name, abi) do
    generate_file(tmp, name, abi_only_file(tmp, name, abi))
  end

  defp generated_module(contents) do
    [{module, _bytecode}] = Code.compile_string(contents)
    module
  end

  defp refute_bytecode_emission(contents) do
    refute contents =~ "def exec_vm_"
    refute contents =~ "def bytecode"
    refute contents =~ "def deployed_bytecode"
  end

  defp assert_bytecode_emission(contents) do
    assert contents =~ "def exec_vm_"
    assert contents =~ "def bytecode"
    assert contents =~ "def deployed_bytecode"
  end

  defp public_defs(contents) do
    ~r/^\s{2}def\s+([a-z_][a-zA-Z0-9_!?]*)(?:\(|\b)/m
    |> Regex.scan(contents, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp annotation_stanza(contents, name) do
    pattern = ~r/@doc (?:\"[^\"]+\"|false)\n\s+@spec #{name}\([\s\S]*?\n\s+def #{name}(?:\(|\b)/

    Regex.run(pattern, contents)
  end

  describe "blank_bytecode?/1 predicate" do
    test "literal \"0x\" bytecode emits no exec_vm_* and no bytecode/0", %{tmp: tmp} do
      refute_bytecode_emission(generate(tmp, "BlankZeroX", "0x"))
    end

    test "absent bytecode key emits no exec_vm_* and no bytecode/0", %{tmp: tmp} do
      refute_bytecode_emission(generate(tmp, "BlankAbsent", :absent))
    end

    test "real bytecode emits exec_vm_* for :pure selectors", %{tmp: tmp} do
      assert_bytecode_emission(generate(tmp, "RealBytecode", "0x6080604052348015"))
    end

    test "generated preintern helpers include specs on private functions", %{tmp: tmp} do
      contents = generate(tmp, "SpecPreintern", "0x6080604052348015")

      assert contents =~ "@spec preintern_return_atoms!(term()) :: term()"
      assert contents =~ "defp preintern_return_atoms!(types) when is_list(types)"
      assert contents =~ "@spec preintern_name_atom!(term()) :: term()"
      assert contents =~ "defp preintern_name_atom!(name) when is_binary(name) and name != \"\""
    end

    test "whitespace-only bytecode is treated as blank", %{tmp: tmp} do
      refute_bytecode_emission(generate(tmp, "BlankWhitespace", "   "))
    end
  end

  describe "RPC-side API survives bytecode dropout" do
    test "encode_/call_/execute_ helpers are emitted even without bytecode", %{tmp: tmp} do
      contents = generate(tmp, "RpcOnly", "0x")

      assert contents =~ "def encode_ping"
      assert contents =~ "def call_ping"
      assert contents =~ "def execute_ping"
    end

    test "generated public functions include ABI-derived docs and specs", %{tmp: tmp} do
      contents = generate(tmp, "DocumentedRpc", "0x6080604052348015")

      for name <- public_defs(contents) do
        assert annotation_stanza(contents, name)
      end

      assert contents =~ ~S|@doc "Encodes ABI calldata for `encode_ping/ping(uint256)`."|
      assert contents =~ "@spec encode_ping(non_neg_integer()) :: binary()"
      assert contents =~ "@spec ping_selector() :: ABI.FunctionSelector.t()"
      assert contents =~ "@spec decode_ping_call(binary()) :: [non_neg_integer()]"
      assert contents =~ "@spec call_ping(<<_::160>>, non_neg_integer(), Keyword.t()) ::"
      assert contents =~ "@spec exec_vm_ping(non_neg_integer(), Keyword.t()) ::"
      assert contents =~ "@spec bytecode() :: binary()"
      assert contents =~ "@spec deployed_bytecode() :: binary()"
      assert contents =~ "@spec abi() :: [map()]"
    end
  end

  describe "selector shapes" do
    test "constructor helpers use bytecode and tuple field atoms", %{tmp: tmp} do
      abi = [
        %{
          "type" => "constructor",
          "inputs" => [
            %{
              "name" => "config",
              "type" => "tuple",
              "components" => [
                %{"name" => "firstValue", "type" => "uint256"},
                %{"name" => "secondValue", "type" => "address"}
              ]
            }
          ]
        }
      ]

      contents = generate(tmp, "ConstructorOnly", "0x6080", abi)

      assert contents =~ "def encode_constructor(_config = %{first_value: first_value, second_value: second_value})"
      assert contents =~ "bytecode() <> ABI.encode(\"((uint256,address))\""
      assert contents =~ "config = %{first_value: _first_value, second_value: _second_value}"
      assert contents =~ "def prepare_constructor("
      assert contents =~ "def execute_constructor("
    end

    test "event and error selectors emit dedicated decoders and generic dispatchers", %{tmp: tmp} do
      abi = [
        %{
          "type" => "event",
          "name" => "LogThing",
          "inputs" => [%{"name" => "value", "type" => "uint256", "indexed" => false}]
        },
        %{
          "type" => "error",
          "name" => "BadThing",
          "inputs" => [%{"name" => "reason", "type" => "uint256"}]
        }
      ]

      contents = generate(tmp, "EventsAndErrors", :absent, abi)

      assert contents =~ "def log_thing_event_selector"
      assert contents =~ "def encode_log_thing_event(value)"
      assert contents =~ "def decode_log_thing_event(topics, data) when is_list(topics)"
      assert contents =~ "def decode_event(\n        [\n          <<"
      assert contents =~ "def bad_thing_selector"
      assert contents =~ "def encode_bad_thing(reason)"
      assert contents =~ "def decode_bad_thing_error(<<"
      assert contents =~ "def decode_error(<<"
    end

    test "duplicate function names receive signature suffixes", %{tmp: tmp} do
      abi = [
        %{
          "type" => "function",
          "name" => "dupe",
          "inputs" => [%{"name" => "value", "type" => "uint256"}],
          "outputs" => [],
          "stateMutability" => "view"
        },
        %{
          "type" => "function",
          "name" => "dupe",
          "inputs" => [%{"name" => "who", "type" => "address"}],
          "outputs" => [],
          "stateMutability" => "view"
        }
      ]

      contents = generate(tmp, "DuplicateNames", :absent, abi)

      assert contents =~ "def dupe_selector"
      assert contents =~ "def dupe_22222abd_selector"
    end

    test "contract name falls back to AST absolute path", %{tmp: tmp} do
      abi = pure_function_abi()
      artifact_path = write_artifact(tmp, "IgnoredName", "0x6080", abi, metadata: false)

      artifact_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("ast", %{"sourceUnit" => 1, "absolutePath" => "/tmp/AstNamed.sol"})
      |> Jason.encode!()
      |> then(&File.write!(artifact_path, &1))

      out_dir = Path.join(tmp, "ast-out")
      File.mkdir_p!(out_dir)

      Gen.run(["--prefix", "gen_test", "--out", out_dir, artifact_path])

      assert File.exists?(Path.join([out_dir, "gen_test", "ast_named.ex"]))
    end
  end

  describe "synthetic ABI generation" do
    test "emits selectors, fallback helpers, and catch-all decoders", %{tmp: tmp} do
      artifact =
        "Synthetic"
        |> solidity_artifact(synthetic_abi(), metadata_json?: true)
        |> put_bytecodes("0x60806040", "0x60806041")

      module =
        tmp
        |> generate_artifact("Synthetic", artifact)
        |> generated_module()

      assert module.contract_name() == "Synthetic"
      assert module.encode_fallback(<<1, 2, 3>>) == <<1, 2, 3>>
      assert module.encode_receive(<<4, 5>>) == <<4, 5>>
      assert is_binary(module.bytecode())
      assert is_binary(module.deployed_bytecode())

      assert %ABI.FunctionSelector{function: "noArgs"} = module.no_args_selector()
      assert %ABI.FunctionSelector{function: "blankName"} = module.blank_name_selector()
      assert %ABI.FunctionSelector{function: "setPair"} = module.set_pair_selector()
      assert %ABI.FunctionSelector{function: "CustomError"} = module.custom_error_selector()
      assert %ABI.FunctionSelector{function: "Pinged"} = module.pinged_event_selector()

      assert module.decode_call(<<0, 0, 0, 0>>) == :not_found
      assert module.decode_error(<<0, 0, 0, 0>>) == :not_found
      assert module.decode_event([<<0::256>>], <<>>) == :not_found
    end

    test "uses AST contract-name fallback when metadata has no compilation target", %{tmp: tmp} do
      contents = generate_artifact(tmp, "AstNamed", ast_artifact("AstNamed", pure_function_abi()))

      assert contents =~ "defmodule GenTest.AstNamed do"
      assert contents =~ ~s("AstNamed")
    end

    test "converts ABI-only JSON into a solidity artifact wrapper", %{tmp: tmp} do
      contents = generate_abi_file(tmp, "AbiOnly", pure_function_abi())

      assert contents =~ "defmodule GenTest.AbiOnly do"
      assert contents =~ ~s("AbiOnly")
      assert contents =~ "def encode_ping"
    end
  end

  describe "bytecode shape coverage" do
    test "init bytecode without deployed bytecode emits no exec_vm helpers", %{tmp: tmp} do
      artifact =
        "InitOnly"
        |> solidity_artifact(pure_function_abi())
        |> put_bytecodes("0x60806040", :absent)

      contents = generate_artifact(tmp, "InitOnly", artifact)

      assert contents =~ "def bytecode"
      refute contents =~ "def exec_vm_ping"
      refute contents =~ "deployed_bytecode()"
      refute contents =~ "def deployed_bytecode"

      module = generated_module(contents)

      assert function_exported?(module, :encode_ping, 1)
      refute function_exported?(module, :exec_vm_ping, 1)
    end

    test "deployed bytecode without init bytecode emits exec_vm helpers", %{tmp: tmp} do
      artifact =
        "DeployedOnly"
        |> solidity_artifact(pure_function_abi())
        |> put_bytecodes(:absent, "0x60806041")

      contents = generate_artifact(tmp, "DeployedOnly", artifact)

      refute contents =~ "def bytecode"
      assert contents =~ "def exec_vm_ping"
      assert contents =~ "def deployed_bytecode"

      module = generated_module(contents)

      assert function_exported?(module, :exec_vm_ping, 1)
      assert function_exported?(module, :deployed_bytecode, 0)
      refute function_exported?(module, :bytecode, 0)
    end
  end

  describe "error paths" do
    test "invalid JSON shape raises a generator-specific file error", %{tmp: tmp} do
      path = Path.join(tmp, "Invalid.json")
      File.write!(path, Jason.encode!(%{"not_abi" => true}))

      assert_raise Gen.InvalidFileError, ~r/Invalid Solidity output or ABI/, fn ->
        generate_file(tmp, "Invalid", path)
      end
    end

    test "missing CLI arguments raise usage", %{tmp: _tmp} do
      assert_raise RuntimeError, ~r/usage: mix cartouche\.gen/, fn ->
        Gen.run([])
      end
    end
  end
end

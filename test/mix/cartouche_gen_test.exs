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

  defp write_artifact(tmp, name, bytecode_object, abi, opts) do
    bytecode =
      case bytecode_object do
        :absent -> nil
        v -> %{"object" => v}
      end

    artifact = %{
      "abi" => abi,
      "metadata" => metadata_for(name, opts)
    }

    artifact =
      if bytecode do
        artifact
        |> Map.put("bytecode", bytecode)
        |> Map.put("deployedBytecode", bytecode)
      else
        artifact
      end

    path = Path.join(tmp, "#{name}.json")
    File.write!(path, Jason.encode!(artifact))
    path
  end

  defp metadata_for(name, opts) do
    if Keyword.get(opts, :metadata, true) do
      %{"settings" => %{"compilationTarget" => %{"src/#{name}.sol" => name}}}
    end
  end

  defp generate(tmp, name, bytecode_object, abi \\ pure_function_abi(), opts \\ []) do
    artifact_path = write_artifact(tmp, name, bytecode_object, abi, opts)
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
      assert contents =~ "def dupe_"
      assert contents =~ "_selector"
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
end

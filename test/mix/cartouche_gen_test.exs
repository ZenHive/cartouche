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

  defp event_and_error_abi do
    [
      %{
        "type" => "event",
        "name" => "Pinged",
        "inputs" => [%{"name" => "who", "type" => "address", "indexed" => true}],
        "anonymous" => false
      },
      %{
        "type" => "error",
        "name" => "Panic",
        "inputs" => [%{"name" => "code", "type" => "uint256", "internalType" => "uint256"}]
      }
    ]
  end

  defp constructor_fallback_receive_abi do
    [
      %{
        "type" => "constructor",
        "inputs" => [%{"name" => "seed", "type" => "uint256", "internalType" => "uint256"}]
      },
      %{"type" => "fallback", "stateMutability" => "payable"},
      %{"type" => "receive", "stateMutability" => "payable"}
    ]
  end

  defp struct_return_function_abi do
    [
      %{
        "type" => "function",
        "name" => "nested",
        "inputs" => [],
        "outputs" => [
          %{
            "name" => "outerField",
            "type" => "tuple",
            "components" => [
              %{"name" => "innerValue", "type" => "uint256", "internalType" => "uint256"},
              %{
                "name" => "items",
                "type" => "tuple[]",
                "components" => [%{"name" => "leafNode", "type" => "bool", "internalType" => "bool"}]
              }
            ]
          }
        ],
        "stateMutability" => "pure"
      }
    ]
  end

  defp write_artifact(tmp, name, bytecode_object, abi) do
    bytecode =
      case bytecode_object do
        :absent -> nil
        v -> %{"object" => v}
      end

    artifact = %{
      "abi" => abi,
      "metadata" => %{
        "settings" => %{
          "compilationTarget" => %{"src/#{name}.sol" => name}
        }
      }
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

  defp generate(tmp, name, bytecode_object, abi \\ pure_function_abi()) do
    artifact_path = write_artifact(tmp, name, bytecode_object, abi)
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

  describe "decode_structs atom pre-interning" do
    test "emits snake_case return-field atoms from nested output tuples", %{tmp: tmp} do
      contents = generate(tmp, "StructAtoms", "0x6080604052348015", struct_return_function_abi())

      assert contents =~ "@cartouche_decode_struct_atoms [:inner_value, :items, :leaf_node, :outer_field]"
      assert contents =~ "def _cartouche_decode_struct_atoms"
      refute contents =~ ~s|name: :outer_field|
      assert contents =~ ~s|name: "outerField"|
    end
  end

  describe "selector type emission" do
    test "emits event and error decoders with generic dispatch fallbacks", %{tmp: tmp} do
      contents = generate(tmp, "Signals", "0x6080604052348015", event_and_error_abi())

      assert contents =~ "def pinged_event_selector"
      assert contents =~ "def encode_pinged_event"
      assert contents =~ "def decode_pinged_event"
      assert contents =~ "def decode_event("
      assert contents =~ "| _"
      assert contents =~ "def panic_selector"
      assert contents =~ "def encode_panic"
      assert contents =~ "def decode_panic_error"
      assert contents =~ "def decode_error(<<"
    end

    test "emits constructor, fallback, and receive encode/execute paths", %{tmp: tmp} do
      contents = generate(tmp, "Lifecycle", "0x6080604052348015", constructor_fallback_receive_abi())

      assert contents =~ "def encode_constructor(seed)"
      assert contents =~ "def prepare_constructor(seed, opts \\\\ [])"
      assert contents =~ "def execute_constructor(seed, opts \\\\ [])"
      assert contents =~ "def encode_fallback(data)"
      assert contents =~ "def prepare_fallback(contract, data, opts \\\\ [])"
      assert contents =~ "def execute_fallback(contract, data, opts \\\\ [])"
      assert contents =~ "def encode_receive(data)"
      assert contents =~ "def execute_receive(contract, data, opts \\\\ [])"
    end
  end
end

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

  defp overloaded_function_abi do
    [
      function_abi("ping", [%{"name" => "x", "type" => "uint8", "internalType" => "uint8"}]),
      function_abi("ping", [%{"name" => "x", "type" => "uint256", "internalType" => "uint256"}])
    ]
  end

  defp event_and_error_abi do
    [
      %{
        "type" => "event",
        "name" => "Pinged",
        "inputs" => [
          %{"name" => "who", "type" => "address", "internalType" => "address", "indexed" => true},
          %{"name" => "amount", "type" => "uint256", "internalType" => "uint256", "indexed" => false}
        ],
        "anonymous" => false
      },
      %{
        "type" => "error",
        "name" => "Denied",
        "inputs" => [%{"name" => "reason", "type" => "string", "internalType" => "string"}]
      }
    ]
  end

  defp constructor_and_fallback_abi do
    [
      %{
        "type" => "constructor",
        "inputs" => [%{"name" => "owner", "type" => "address", "internalType" => "address"}],
        "stateMutability" => "nonpayable"
      },
      %{"type" => "fallback", "stateMutability" => "payable"},
      %{"type" => "receive", "stateMutability" => "payable"}
    ]
  end

  defp tuple_function_abi do
    [
      function_abi("store", [
        %{
          "name" => "record",
          "type" => "tuple",
          "internalType" => "struct Record",
          "components" => [
            %{"name" => "id", "type" => "uint256", "internalType" => "uint256"},
            %{"name" => "owner", "type" => "address", "internalType" => "address"}
          ]
        }
      ])
    ]
  end

  defp function_abi(name, inputs) do
    %{
      "type" => "function",
      "name" => name,
      "inputs" => inputs,
      "outputs" => [],
      "stateMutability" => "nonpayable"
    }
  end

  defp write_artifact(tmp, name, bytecode_object) do
    bytecode =
      case bytecode_object do
        :absent -> nil
        v -> %{"object" => v}
      end

    artifact = %{
      "abi" => pure_function_abi(),
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

  defp write_artifact_with_abi(tmp, name, abi, extra \\ %{}) do
    artifact =
      Map.merge(
        %{
          "abi" => abi,
          "metadata" => %{
            "settings" => %{
              "compilationTarget" => %{"src/#{name}.sol" => name}
            }
          }
        },
        extra
      )

    path = Path.join(tmp, "#{name}.json")
    File.write!(path, Jason.encode!(artifact))
    path
  end

  defp generated_path(out_dir, name) do
    out_dir
    |> Path.join("gen_test")
    |> Path.join("#{Macro.underscore(name)}.ex")
  end

  defp generate(tmp, name, bytecode_object) do
    artifact_path = write_artifact(tmp, name, bytecode_object)
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
    |> generated_path(name)
    |> File.read!()
  end

  defp generate_from_artifact(tmp, artifact_path, name) do
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
    |> generated_path(name)
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

  describe "artifact shape handling" do
    test "derives the contract module name from ast when metadata is absent", %{tmp: tmp} do
      artifact_path =
        write_artifact_with_abi(tmp, "AstNamed", pure_function_abi(), %{
          "metadata" => nil,
          "ast" => %{"sourceUnit" => 1, "absolutePath" => "contracts/AstNamed.sol"}
        })

      contents = generate_from_artifact(tmp, artifact_path, "AstNamed")

      assert contents =~ "defmodule GenTest.AstNamed do"
      assert contents =~ "def contract_name do\n    \"AstNamed\"\n  end"
    end

    test "accepts a raw ABI list and names the module from the file", %{tmp: tmp} do
      artifact_path = Path.join(tmp, "ListOnly.json")
      File.write!(artifact_path, Jason.encode!(pure_function_abi()))

      contents = generate_from_artifact(tmp, artifact_path, "ListOnly")

      assert contents =~ "defmodule GenTest.ListOnly do"
      assert contents =~ "def contract_name do\n    \"ListOnly\"\n  end"
    end

    test "rejects JSON that is neither an artifact nor an ABI list", %{tmp: tmp} do
      artifact_path = Path.join(tmp, "Invalid.json")
      File.write!(artifact_path, Jason.encode!(%{"not_abi" => true}))

      assert_raise Gen.InvalidFileError, ~r/Invalid Solidity output or ABI/, fn ->
        generate_from_artifact(tmp, artifact_path, "Invalid")
      end
    end
  end

  describe "ABI item generation" do
    test "renames overloaded functions with selector suffixes", %{tmp: tmp} do
      artifact_path = write_artifact_with_abi(tmp, "Overloaded", overloaded_function_abi())

      contents = generate_from_artifact(tmp, artifact_path, "Overloaded")

      assert contents =~ "def encode_ping(x)"
      assert contents =~ "def encode_ping_"
    end

    test "emits event and error decoders", %{tmp: tmp} do
      artifact_path = write_artifact_with_abi(tmp, "EventsAndErrors", event_and_error_abi())

      contents = generate_from_artifact(tmp, artifact_path, "EventsAndErrors")

      assert contents =~ "def decode_pinged_event(topics, data) when is_list(topics)"
      assert contents =~ "def decode_denied_error(<<"
      assert contents =~ "def decode_event("
      assert contents =~ "def decode_error(<<"
    end

    test "emits constructor, fallback, and receive wrappers when bytecode exists", %{tmp: tmp} do
      artifact_path =
        write_artifact_with_abi(tmp, "Lifecycle", constructor_and_fallback_abi(), %{
          "bytecode" => %{"object" => "0x6080604052348015"},
          "deployedBytecode" => %{"object" => "0x6080604052"}
        })

      contents = generate_from_artifact(tmp, artifact_path, "Lifecycle")

      assert contents =~ "def encode_constructor(owner)"
      assert contents =~ "def encode_fallback(data)"
      assert contents =~ "def encode_receive(data)"
      assert contents =~ "def bytecode"
      assert contents =~ "def deployed_bytecode"
    end

    test "emits struct-shaped tuple arguments as map patterns", %{tmp: tmp} do
      artifact_path = write_artifact_with_abi(tmp, "TupleInput", tuple_function_abi())

      contents = generate_from_artifact(tmp, artifact_path, "TupleInput")

      assert contents =~ "def encode_store(_record = %{id: id, owner: owner})"
      assert contents =~ "{id, owner}"
    end
  end
end

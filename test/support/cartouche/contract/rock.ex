defmodule Cartouche.Contract.Rock do
  @moduledoc false
  use Cartouche.Hex

  alias Cartouche.Transaction.V2

  @doc false
  @spec contract_name() :: term()
  def contract_name do
    "Rock"
  end

  @doc false
  @spec stumble_selector() :: term()
  def stumble_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "Stumble",
      function_type: :error,
      returns: nil,
      state_mutability: nil,
      types: [%{name: "c", type: {:uint, 256}}]
    }
  end

  @doc false
  @spec encode_stumble(term()) :: term()
  def encode_stumble(c) do
    ABI.encode(stumble_selector(), [c])
  end

  @doc false
  @spec decode_stumble_error(term()) :: term()
  def decode_stumble_error(<<211, 49, 186, 152>> <> error) do
    _signature = hex!("0xd331ba98")
    ABI.decode(stumble_selector(), error)
  end

  @doc false
  @spec jam_selector() :: term()
  def jam_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "jam",
      function_type: :function,
      returns: [
        %{
          name: "f",
          type: {:tuple, [%{name: "beats", type: {:uint, 256}}, %{name: "song", type: :string}]}
        }
      ],
      state_mutability: :pure,
      types: [%{name: "beats", type: {:uint, 256}}]
    }
  end

  @doc false
  @spec encode_jam(term()) :: term()
  def encode_jam(beats) do
    ABI.encode(jam_selector(), [beats])
  end

  @doc false
  @spec prepare_jam(term(), term(), term()) :: term()
  def prepare_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_jam(beats), opts)
  end

  @doc false
  @spec build_trx_jam(term(), term()) :: term()
  def build_trx_jam(contract, beats) do
    %V2{destination: contract, data: encode_jam(beats)}
  end

  @doc false
  @spec call_jam(term(), term(), term()) :: term()
  def call_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_jam(contract, beats), opts)
  end

  @doc false
  @spec estimate_gas_jam(term(), term(), term()) :: term()
  def estimate_gas_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_jam(contract, beats), opts)
  end

  @doc false
  @spec execute_jam(term(), term(), term()) :: term()
  def execute_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_jam(beats), opts)
  end

  @doc false
  @spec decode_jam_call(term()) :: term()
  def decode_jam_call(<<191, 104, 23, 16>> <> calldata) do
    _signature = hex!("0xbf681710")
    ABI.decode(jam_selector(), calldata)
  end

  @doc false
  @spec exec_vm_jam(term(), term()) :: term()
  def exec_vm_jam(beats, exec_opts \\ []) do
    case Cartouche.VM.exec_call(deployed_bytecode(), encode_jam(beats), exec_opts) do
      {:ok, return_data} ->
        case ABI.decode(%ABI.FunctionSelector{types: jam_selector().returns}, return_data, decode_structs: true) do
          m when is_map(m) -> {:ok, m}
          [decoded] -> {:ok, decoded}
          els -> {:ok, els}
        end

      {:revert, revert_data} ->
        case decode_error(revert_data) do
          {:ok, error, data} -> {:revert, error, data}
          :not_found -> {:revert, "Unknown", revert_data}
        end
    end
  end

  @doc false
  @spec exec_vm_jam_raw(term(), term()) :: term()
  def exec_vm_jam_raw(beats, exec_opts \\ []) do
    Cartouche.VM.exec_call(deployed_bytecode(), encode_jam(beats), exec_opts)
  end

  @doc false
  @spec stumble_144e59d6_selector() :: term()
  def stumble_144e59d6_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "stumble",
      function_type: :function,
      returns: [%{name: "", type: {:uint, 256}}],
      state_mutability: :pure,
      types: []
    }
  end

  @doc false
  @spec encode_stumble_144e59d6() :: term()
  def encode_stumble_144e59d6 do
    ABI.encode(stumble_144e59d6_selector(), [])
  end

  @doc false
  @spec prepare_stumble_144e59d6(term(), term()) :: term()
  def prepare_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_stumble_144e59d6(), opts)
  end

  @doc false
  @spec build_trx_stumble_144e59d6(term()) :: term()
  def build_trx_stumble_144e59d6(contract) do
    %V2{destination: contract, data: encode_stumble_144e59d6()}
  end

  @doc false
  @spec call_stumble_144e59d6(term(), term()) :: term()
  def call_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_stumble_144e59d6(contract), opts)
  end

  @doc false
  @spec estimate_gas_stumble_144e59d6(term(), term()) :: term()
  def estimate_gas_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_stumble_144e59d6(contract), opts)
  end

  @doc false
  @spec execute_stumble_144e59d6(term(), term()) :: term()
  def execute_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_stumble_144e59d6(), opts)
  end

  @doc false
  @spec decode_stumble_144e59d6_call(term()) :: term()
  def decode_stumble_144e59d6_call(<<20, 78, 89, 214>> <> calldata) do
    _signature = hex!("0x144e59d6")
    ABI.decode(stumble_144e59d6_selector(), calldata)
  end

  @doc false
  @spec exec_vm_stumble_144e59d6(term()) :: term()
  def exec_vm_stumble_144e59d6(exec_opts \\ []) do
    case Cartouche.VM.exec_call(deployed_bytecode(), encode_stumble_144e59d6(), exec_opts) do
      {:ok, return_data} ->
        case ABI.decode(
               %ABI.FunctionSelector{types: stumble_144e59d6_selector().returns},
               return_data,
               decode_structs: true
             ) do
          m when is_map(m) -> {:ok, m}
          [decoded] -> {:ok, decoded}
          els -> {:ok, els}
        end

      {:revert, revert_data} ->
        case decode_error(revert_data) do
          {:ok, error, data} -> {:revert, error, data}
          :not_found -> {:revert, "Unknown", revert_data}
        end
    end
  end

  @doc false
  @spec exec_vm_stumble_144e59d6_raw(term()) :: term()
  def exec_vm_stumble_144e59d6_raw(exec_opts \\ []) do
    Cartouche.VM.exec_call(deployed_bytecode(), encode_stumble_144e59d6(), exec_opts)
  end

  @doc false
  @spec decode_call(term()) :: term()
  def decode_call(<<191, 104, 23, 16>> <> _ = calldata) do
    _signature = hex!("0xbf681710")
    {:ok, "jam", decode_jam_call(calldata)}
  end

  def decode_call(<<20, 78, 89, 214>> <> _ = calldata) do
    _signature = hex!("0x144e59d6")
    {:ok, "stumble", decode_stumble_144e59d6_call(calldata)}
  end

  def decode_call(_) do
    :not_found
  end

  @doc false
  @spec decode_event(term(), term()) :: term()
  def decode_event(_, _) do
    :not_found
  end

  @doc false
  @spec decode_error(term()) :: term()
  def decode_error(<<211, 49, 186, 152>> <> _ = error) do
    _signature = hex!("0xd331ba98")
    {:ok, "Stumble", decode_stumble_error(error)}
  end

  def decode_error(_) do
    if true do
      :not_found
    else
      {:ok, "Impossible", <<>>}
    end
  end

  @doc false
  @spec bytecode() :: term()
  def bytecode do
    hex!(
      "608060405234801561000f575f80fd5b506103458061001d5f395ff3fe608060405234801561000f575f80fd5b5060043610610034575f3560e01c8063144e59d614610038578063bf68171014610056575b5f80fd5b610040610086565b60405161004d919061014f565b60405180910390f35b610070600480360381019061006b9190610196565b6100c5565b60405161007d9190610294565b60405180910390f35b5f60376040517fd331ba980000000000000000000000000000000000000000000000000000000081526004016100bc91906102f6565b60405180910390fd5b6100cd61011e565b60405180604001604052808381526020016040518060400160405280600f81526020017f42616e64206f6e207468652052756e00000000000000000000000000000000008152508152509050919050565b60405180604001604052805f8152602001606081525090565b5f819050919050565b61014981610137565b82525050565b5f6020820190506101625f830184610140565b92915050565b5f80fd5b61017581610137565b811461017f575f80fd5b50565b5f813590506101908161016c565b92915050565b5f602082840312156101ab576101aa610168565b5b5f6101b884828501610182565b91505092915050565b6101ca81610137565b82525050565b5f81519050919050565b5f82825260208201905092915050565b5f5b838110156102075780820151818401526020810190506101ec565b5f8484015250505050565b5f601f19601f8301169050919050565b5f61022c826101d0565b61023681856101da565b93506102468185602086016101ea565b61024f81610212565b840191505092915050565b5f604083015f83015161026f5f8601826101c1565b50602083015184820360208601526102878282610222565b9150508091505092915050565b5f6020820190508181035f8301526102ac818461025a565b905092915050565b5f819050919050565b5f819050919050565b5f6102e06102db6102d6846102b4565b6102bd565b610137565b9050919050565b6102f0816102c6565b82525050565b5f6020820190506103095f8301846102e7565b9291505056fea26469706673582212202c77c48aba2ef6154e6648ed7c485abc0d9fe67fb484d56a7e986a6ee7c7734764736f6c63430008170033"
    )
  end

  @doc false
  @spec deployed_bytecode() :: term()
  def deployed_bytecode do
    hex!(
      "608060405234801561000f575f80fd5b5060043610610034575f3560e01c8063144e59d614610038578063bf68171014610056575b5f80fd5b610040610086565b60405161004d919061014f565b60405180910390f35b610070600480360381019061006b9190610196565b6100c5565b60405161007d9190610294565b60405180910390f35b5f60376040517fd331ba980000000000000000000000000000000000000000000000000000000081526004016100bc91906102f6565b60405180910390fd5b6100cd61011e565b60405180604001604052808381526020016040518060400160405280600f81526020017f42616e64206f6e207468652052756e00000000000000000000000000000000008152508152509050919050565b60405180604001604052805f8152602001606081525090565b5f819050919050565b61014981610137565b82525050565b5f6020820190506101625f830184610140565b92915050565b5f80fd5b61017581610137565b811461017f575f80fd5b50565b5f813590506101908161016c565b92915050565b5f602082840312156101ab576101aa610168565b5b5f6101b884828501610182565b91505092915050565b6101ca81610137565b82525050565b5f81519050919050565b5f82825260208201905092915050565b5f5b838110156102075780820151818401526020810190506101ec565b5f8484015250505050565b5f601f19601f8301169050919050565b5f61022c826101d0565b61023681856101da565b93506102468185602086016101ea565b61024f81610212565b840191505092915050565b5f604083015f83015161026f5f8601826101c1565b50602083015184820360208601526102878282610222565b9150508091505092915050565b5f6020820190508181035f8301526102ac818461025a565b905092915050565b5f819050919050565b5f819050919050565b5f6102e06102db6102d6846102b4565b6102bd565b610137565b9050919050565b6102f0816102c6565b82525050565b5f6020820190506103095f8301846102e7565b9291505056fea26469706673582212202c77c48aba2ef6154e6648ed7c485abc0d9fe67fb484d56a7e986a6ee7c7734764736f6c63430008170033"
    )
  end
end

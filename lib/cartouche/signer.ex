defmodule Cartouche.Signer do
  @moduledoc """
  Cartouche.Signer is a GenServer which can sign messages. This module takes an
  mfa (mod, func, args triple) which defines how to actually sign messages.
  For instance, `Cartouche.Signer.Curvy` will sign with a public key, or
  `Cartouche.Signer.CloudKMS` will sign using a GCP Cloud KMS key. In either
  case, the caller should start the GenServer, and then call:
  `Cartouche.Signer.sign(MySigner, "message")`. This should return back a
  properly signed message.

  Note: we also enforce that a given signer process knows its public key,
  such that we can verify signatures recovery bits. That is, since CloudKMS
  and other signing tools don't return a recovery bit, necessary for Ethereum,
  we test all 4 possible bits to make sure a signature recovers to the correct
  signer address, but we need to know what that address should be to accomplish
  this task.

  Additionally, chain_id is used to return EIP-155 compliant signatures.
  """
  use Descripex, namespace: "/ethereum/signer"
  use GenServer
  use Cartouche.Hex

  alias Cartouche.Signer.Default

  require Logger

  api(:child_spec, "Build the supervisor child specification for a signer process.",
    params: [
      init_arg: [
        kind: :value,
        description: "Initialization argument passed by a supervisor when starting Cartouche.Signer."
      ]
    ],
    returns: %{
      type: :supervisor_child_spec,
      description: "Supervisor child spec map that starts Cartouche.Signer."
    }
  )

  api(:start_link, "Start a signer process backed by the provided signing MFA.",
    params: [
      signer_options: [
        kind: :value,
        description: "Keyword list containing `:mfa` as `{module, function, args}` and `:name` as the GenServer name."
      ]
    ],
    returns: %{
      type: :genserver_on_start,
      description: "`{:ok, pid}` when the signer starts, or the standard GenServer start error tuple."
    }
  )

  @doc """
  Starts a new Cartouche.Signer process.
  """
  @spec start_link(mfa: {module(), atom(), [any()]}, name: GenServer.name()) :: GenServer.on_start()
  def start_link(mfa: mfa, name: name) do
    Logger.info("Starting Cartouche.Signer #{name}...")
    chain_id = Cartouche.Application.chain_id()

    GenServer.start_link(
      __MODULE__,
      %{mfa: mfa, name: name, chain_id: chain_id},
      name: name
    )
  end

  @doc false
  @impl true
  def init(state) do
    {:ok, state}
  end

  api(:sign, "Sign a message with a running signer process.",
    params: [
      message: [kind: :value, description: "Message bytes or string to sign."],
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."],
      opts: [kind: :value, default: [], description: "Keyword options for signing."]
    ],
    opts: [
      chain_id: [
        kind: :value,
        description:
          "Chain id used to produce an EIP-155-compliant signature; defaults to the signer's configured chain id."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, signature}` with the 65-byte Ethereum signature, or `{:error, reason}` when signing or recovery fails."
    },
    composes_with: [:sign_direct]
  )

  @doc """
  Signs a message using this signing key.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, sig} = Cartouche.Signer.sign("test", signer_proc)
      iex> Cartouche.Recover.recover_eth("test", sig)
      ...> |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, <<_r::256, _s::256, v::binary>>} = Cartouche.Signer.sign("test", signer_proc, chain_id: 0x05f5e0ff)
      iex> :binary.decode_unsigned(v)
      0x05f5e0ff * 2 + 35 + 1
  """
  @spec sign(String.t(), GenServer.name(), Keyword.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def sign(message, name \\ Default, opts \\ []) do
    chain_id = Keyword.get(opts, :chain_id, GenServer.call(name, :get_chain_id))
    GenServer.call(name, {:sign, {message, chain_id}})
  end

  api(:address, "Get the Ethereum address controlled by a signer process.",
    params: [
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."]
    ],
    returns: %{type: :ethereum_address, description: "20-byte Ethereum address for the signer."}
  )

  @doc """
  Gets the address for this signer.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> Cartouche.Signer.address(signer_proc) |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec address(GenServer.name()) :: Cartouche.address()
  def address(name \\ Default) do
    GenServer.call(name, :get_address)
  end

  api(:chain_id, "Get the chain id configured for a signer process.",
    params: [
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."]
    ],
    returns: %{type: :integer, description: "Configured Ethereum chain id."}
  )

  @doc """
  Gets the chain id for this signer.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> Cartouche.Signer.chain_id(signer_proc)
      5
  """
  @spec chain_id(GenServer.name()) :: integer()
  def chain_id(name \\ Default) do
    GenServer.call(name, :get_chain_id)
  end

  @doc false
  @impl true
  def handle_call({:sign, {message, chain_id}}, _from, %{address: address, mfa: mfa} = state) do
    {:reply, sign_direct(message, address, mfa, chain_id), state}
  end

  # Note absence of address in state, find it and set it and then sign. Address will be cached on next signing.
  def handle_call({:sign, {message, chain_id}}, _from, %{name: name, mfa: {mod, _fn, args} = mfa} = state) do
    {:ok, address} = apply(mod, :get_address, args)
    Logger.info("Cartouche.Signer #{name} signing with address #{to_address(address)}")

    {:reply, sign_direct(message, address, mfa, chain_id), Map.put(state, :address, address)}
  end

  # Reads address from state, or finds and memoize address on first call.
  def handle_call(:get_address, _from, %{address: address} = state) do
    {:reply, address, state}
  end

  def handle_call(:get_address, _from, %{name: name, mfa: {mod, _fn, args}} = state) do
    {:ok, address} = apply(mod, :get_address, args)
    Logger.info("Cartouche.Signer #{name} signing with address #{to_address(address)}")
    {:reply, address, Map.put(state, :address, address)}
  end

  def handle_call(:get_chain_id, _from, %{chain_id: chain_id} = state) do
    {:reply, chain_id, state}
  end

  api(:sign_direct, "Sign a message directly with a signing MFA and known signer address.",
    params: [
      message: [kind: :value, description: "Message bytes or string to sign."],
      address: [kind: :value, description: "20-byte Ethereum address expected to recover from the signature."],
      signer_mfa: [
        kind: :value,
        description: "`{module, function, args}` tuple that performs the raw secp256k1 signature."
      ],
      chain_id_or_name: [
        kind: :value,
        description: "Ethereum chain id or configured chain name used for EIP-155 `v` calculation."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, signature}` with the 65-byte Ethereum signature, or `{:error, reason}` when signing or recovery fails."
    }
  )

  @doc """
  Directly sign a message, not using a signer process.

  This is mostly used internally, but can be used safely externally as well.
  """
  @spec sign_direct(String.t(), binary(), {module(), atom(), [any()]}, integer()) ::
          {:ok, binary()} | {:error, String.t()}
  def sign_direct(message, address, {mod, fun, args}, chain_id_or_name) do
    with {:ok,
          %Curvy.Signature{
            crv: :secp256k1,
            r: r,
            recid: nil,
            s: s
          } = signature} <- apply(mod, fun, [message] ++ args),
         {:ok, recid} <- Cartouche.Recover.find_recid(message, signature, address) do
      # EIP-155
      chain_id = Cartouche.Chain.parse_id(chain_id_or_name)
      v = if chain_id == 0, do: 27 + recid, else: chain_id * 2 + 35 + recid

      {:ok, Hex.encode_bytes(r, 32) <> Hex.encode_bytes(s, 32) <> :binary.encode_unsigned(v)}
    end
  end
end

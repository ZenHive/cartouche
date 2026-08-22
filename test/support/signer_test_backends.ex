defmodule Cartouche.SignerTest.FixedSignature do
  @moduledoc false

  @doc false
  @spec sign(binary(), Curvy.Signature.t()) :: {:ok, Curvy.Signature.t()}
  def sign(_message, %Curvy.Signature{} = signature), do: {:ok, signature}

  @doc false
  @spec get_address(Curvy.Signature.t()) :: {:ok, binary()}
  def get_address(_signature) do
    {:ok, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7", case: :mixed)}
  end
end

defmodule Cartouche.SignerTest.HighSBackend do
  @moduledoc false
  @behaviour Cartouche.Signer.Backend

  @impl true
  @spec algorithm({binary(), Curvy.Signature.t()}) :: :secp256k1
  def algorithm(_config), do: :secp256k1

  @impl true
  @spec public_key({binary(), Curvy.Signature.t()}) :: {:ok, binary()} | {:error, String.t()}
  def public_key({priv, _signature}), do: Cartouche.Signer.Curvy.public_key(priv)

  @impl true
  @spec sign_payload(<<_::256>>, {binary(), Curvy.Signature.t()}) :: {:ok, Curvy.Signature.t()}
  def sign_payload(_digest, {_priv, signature}), do: {:ok, signature}
end

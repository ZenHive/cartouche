defmodule Cartouche.Solana.Test.Signer do
  @moduledoc false

  # RFC 8032 Test 1 seed
  @test_seed Base.decode16!(
               "9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60",
               case: :upper
             )

  @doc false
  @spec test_seed() :: binary()
  def test_seed, do: @test_seed

  @doc false
  @spec start_signer(atom() | nil) :: atom()
  def start_signer(name \\ nil) do
    name =
      case name do
        nil -> String.to_atom("SolTestSigner#{System.unique_integer([:positive])}")
        name -> name
      end

    {:ok, _pid} =
      Cartouche.Solana.Signer.start_link(
        mfa: {Cartouche.Solana.Signer.Ed25519, :sign, [@test_seed]},
        name: name
      )

    name
  end
end

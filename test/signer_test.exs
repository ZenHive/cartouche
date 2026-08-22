defmodule Cartouche.SignerTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Signer
  alias Cartouche.Signer.Curvy

  doctest Signer

  @priv_key ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
  @address ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7]

  describe "address/0 and chain_id/0 default name" do
    # The application supervises a signer under the default
    # `Cartouche.Signer.Default` name (config :cartouche, :signer), so the
    # arg-less `address/0` and `chain_id/0` clauses resolve against it.
    test "address/0 returns a 20-byte address using the default name" do
      assert <<_::160>> = Signer.address()
    end

    test "chain_id/0 returns the configured chain id using the default name" do
      # config/test.exs sets :chain_id to :goerli (5).
      assert Signer.chain_id() == 5
    end
  end

  describe "sign_direct/4" do
    test "produces a 65-byte EIP-155 signature recoverable to the address" do
      mfa = {Curvy, :sign, [@priv_key]}

      assert {:ok, <<_r::256, _s::256, _v::binary>> = sig} =
               Signer.sign_direct("test", @address, mfa, 0)

      assert byte_size(sig) == 65
      assert Cartouche.Recover.recover_eth("test", sig) == @address
    end
  end

  describe "{backend, config} carrier (pure-payload path)" do
    setup do
      {:ok, pid} = Signer.start_link(mfa: {Curvy, @priv_key}, name: nil)
      %{signer: pid}
    end

    test "address/1 resolves the address from the backend public key", %{signer: signer} do
      assert Signer.address(signer) == @address
    end

    test "sign/2 produces a signature recoverable to the address", %{signer: signer} do
      assert {:ok, sig} = Signer.sign("test", signer)
      assert byte_size(sig) == 65
      assert Cartouche.Recover.recover_eth("test", sig) == @address
    end
  end

  describe "algorithm mismatch" do
    @seed Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")

    test "rejects an ed25519 backend under the Eth signer" do
      {:ok, pid} = Signer.start_link(mfa: {Cartouche.Solana.Signer.Ed25519, @seed}, name: nil)

      assert {:error, {:algorithm_mismatch, :secp256k1, :ed25519}} = Signer.sign("test", pid)
    end
  end
end

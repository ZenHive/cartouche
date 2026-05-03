if Code.ensure_loaded?(Cartouche.Solana.Signer.CloudKMS) do
  defmodule Cartouche.Solana.Signer.CloudKMSTest do
    use ExUnit.Case, async: false

    alias Cartouche.Solana.Signer.CloudKMS

    # Known Ed25519 keypair (RFC 8032 Test 1)
    @seed Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
    @pub Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")

    # Ed25519 SubjectPublicKeyInfo PEM for the above public key.
    # DER = 12-byte prefix (30 2A 30 05 06 03 2B 65 70 03 21 00) + 32-byte pubkey
    @ed25519_pem (fn ->
                    der_prefix =
                      <<0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00>>

                    der = der_prefix <> @pub
                    b64 = Base.encode64(der)
                    "-----BEGIN PUBLIC KEY-----\n#{b64}\n-----END PUBLIC KEY-----\n"
                  end).()

    # Pre-compute a known signature for "test" using the seed
    @test_message "test"
    @test_signature :crypto.sign(:eddsa, :none, @test_message, [@seed, :ed25519])

    # Malformed Ed25519 PEM: valid PEM frame but DER body has the wrong prefix
    # (RSA SubjectPublicKeyInfo OID instead of Ed25519's 1.3.101.112).
    @malformed_der_pem (fn ->
                          rsa_oid_prefix =
                            <<0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2A, 0x86, 0x48, 0x03, 0x21, 0x00>>

                          der = rsa_oid_prefix <> @pub
                          b64 = Base.encode64(der)
                          "-----BEGIN PUBLIC KEY-----\n#{b64}\n-----END PUBLIC KEY-----\n"
                        end).()

    setup do
      Tesla.Mock.mock(fn
        # getPublicKey
        %{
          method: :get,
          url:
            "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version/publicKey"
        } ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                pem: @ed25519_pem,
                algorithm: "EC_SIGN_ED25519",
                pemCrc32c: "0",
                name: "projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version",
                protectionLevel: "HSM"
              })
          }

        # getPublicKey — wrong algorithm
        %{
          method: :get,
          url:
            "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/wrong-algo/cryptoKeyVersions/version/publicKey"
        } ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                pem: @ed25519_pem,
                algorithm: "EC_SIGN_SECP256K1_SHA256",
                pemCrc32c: "0",
                name:
                  "projects/project/locations/location/keyRings/keychain/cryptoKeys/wrong-algo/cryptoKeyVersions/version",
                protectionLevel: "HSM"
              })
          }

        # getPublicKey — malformed DER (correct algo, wrong DER prefix)
        %{
          method: :get,
          url:
            "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/bad-der/cryptoKeyVersions/version/publicKey"
        } ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                pem: @malformed_der_pem,
                algorithm: "EC_SIGN_ED25519",
                pemCrc32c: "0",
                name:
                  "projects/project/locations/location/keyRings/keychain/cryptoKeys/bad-der/cryptoKeyVersions/version",
                protectionLevel: "HSM"
              })
          }

        # asymmetricSign
        %{
          method: :post,
          url:
            "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version:asymmetricSign"
        } ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                signature: Base.encode64(@test_signature),
                signatureCrc32c: "0",
                name: "projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version",
                protectionLevel: "HSM"
              })
          }
      end)

      :ok
    end

    describe "get_address/6" do
      test "extracts Ed25519 public key from PEM" do
        {:ok, pub} =
          CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")

        assert pub == @pub
        assert byte_size(pub) == 32
      end

      test "rejects non-Ed25519 algorithms with descriptive error" do
        assert {:error, "Expected EC_SIGN_ED25519 algorithm, got: EC_SIGN_SECP256K1_SHA256"} =
                 CloudKMS.get_address(
                   "token",
                   "project",
                   "location",
                   "keychain",
                   "wrong-algo",
                   "version"
                 )
      end

      test "rejects malformed Ed25519 DER (wrong SubjectPublicKeyInfo prefix)" do
        assert {:error, "Unexpected DER format for Ed25519 public key"} =
                 CloudKMS.get_address(
                   "token",
                   "project",
                   "location",
                   "keychain",
                   "bad-der",
                   "version"
                 )
      end
    end

    describe "sign/7" do
      test "returns 64-byte signature" do
        {:ok, sig} =
          CloudKMS.sign(
            @test_message,
            "token",
            "project",
            "location",
            "keychain",
            "key",
            "version"
          )

        assert byte_size(sig) == 64
        assert sig == @test_signature
      end

      test "signature verifies" do
        {:ok, sig} =
          CloudKMS.sign(
            @test_message,
            "token",
            "project",
            "location",
            "keychain",
            "key",
            "version"
          )

        assert :crypto.verify(:eddsa, :none, @test_message, sig, [@pub, :ed25519])
      end
    end

    describe "Goth credential path" do
      setup do
        # :meck patches the Goth module globally, so these tests cannot run async.
        :meck.new(Goth, [:passthrough, :no_link])

        on_exit(fn -> :meck.unload(Goth) end)

        :ok
      end

      test "get_address/6 fetches a token from Goth" do
        cred = stub_goth_fetch!(:solana_get_address)

        {:ok, pub} =
          CloudKMS.get_address(cred, "project", "location", "keychain", "key", "version")

        assert pub == @pub
        assert byte_size(pub) == 32
        assert :meck.num_calls(Goth, :fetch!, [cred]) == 1
      end

      test "sign/7 fetches a token from Goth" do
        cred = stub_goth_fetch!(:solana_sign)

        {:ok, sig} =
          CloudKMS.sign(
            @test_message,
            cred,
            "project",
            "location",
            "keychain",
            "key",
            "version"
          )

        assert byte_size(sig) == 64
        assert sig == @test_signature
        assert :meck.num_calls(Goth, :fetch!, [cred]) == 1
      end
    end

    defp stub_goth_fetch!(name) do
      cred = {:goth_credential, name}
      :meck.expect(Goth, :fetch!, fn ^cred -> %{token: "stubbed-token", type: "Bearer"} end)
      cred
    end
  end
end

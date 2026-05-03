defmodule Cartouche.Signer.CloudKMSTest do
  use ExUnit.Case, async: false

  alias Cartouche.Signer.CloudKMS

  doctest CloudKMS

  @address <<221, 166, 65, 178, 167, 106, 74, 124, 54, 23, 129, 91, 177, 50, 129, 221, 32, 123, 116, 213>>
  @signature_der Base.decode64!(
                   "MEQCIGSKMaVlv78Uhc8D+6c9qacz7ISU4rXvH/zhgtaWy++9AiAU2LxgbNAmeYt5KgcgkzchwFsaRZtHTHdruwf5mY8IYQ=="
                 )

  setup do
    Tesla.Mock.mock(fn
      %{
        method: :get,
        url:
          "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version/publicKey"
      } ->
        # https://cloud.google.com/kms/docs/reference/rest/v1/projects.locations.keyRings.cryptoKeys.cryptoKeyVersions/getPublicKey
        # projects/treasury-stage/locations/global/keyRings/
        # treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              pem:
                "-----BEGIN PUBLIC KEY-----\nMFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEI3tE5EGI0XQZMPwFEiYs4cvq3YHiNSDT\n3/ehihlwUqKAYJajnrlRGhSYdqC+bGekcjnQZxyLlw1xXf/pr+yj3g==\n-----END PUBLIC KEY-----\n",
              algorithm: "EC_SIGN_SECP256K1_SHA256",
              pemCrc32c: "1065940272",
              name:
                "projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1",
              protectionLevel: "HSM"
            })
        }

      %{
        method: :get,
        url:
          "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/wrong-algo/cryptoKeyVersions/version/publicKey"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              pem: "-----BEGIN PUBLIC KEY-----\nIRRELEVANT\n-----END PUBLIC KEY-----\n",
              algorithm: "RSA_SIGN_PSS_2048_SHA256",
              pemCrc32c: "0",
              name:
                "projects/project/locations/location/keyRings/keychain/cryptoKeys/wrong-algo/cryptoKeyVersions/version",
              protectionLevel: "SOFTWARE"
            })
        }

      %{
        method: :post,
        url:
          "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version:asymmetricSign"
      } ->
        # https://cloud.google.com/kms/docs/reference/rest/v1/projects.locations.keyRings.cryptoKeys.cryptoKeyVersions/asymmetricSign
        # projects/treasury-stage/locations/global/keyRings/
        # treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1
        # {"digest": {"sha256":"nCL/XyHwuBsRPmP3222pT+3vEbIRm0CIuJZk+5o8tlg="}}
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              signature:
                "MEQCIGSKMaVlv78Uhc8D+6c9qacz7ISU4rXvH/zhgtaWy++9AiAU2LxgbNAmeYt5KgcgkzchwFsaRZtHTHdruwf5mY8IYQ==",
              signatureCrc32c: "3329027021",
              name:
                "projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1",
              protectionLevel: "HSM"
            })
        }
    end)

    :ok
  end

  describe "get_address/6 algorithm validation" do
    test "rejects non-secp256k1 algorithms with descriptive error" do
      assert {:error, "Invalid algorithm: RSA_SIGN_PSS_2048_SHA256"} =
               CloudKMS.get_address("token", "project", "location", "keychain", "wrong-algo", "version")
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
      cred = stub_goth_fetch!(:ethereum_get_address)

      assert {:ok, @address} = CloudKMS.get_address(cred, "project", "location", "keychain", "key", "version")
      assert :meck.num_calls(Goth, :fetch!, [cred]) == 1
    end

    test "sign/7 fetches a token from Goth" do
      cred = stub_goth_fetch!(:ethereum_sign)

      assert {:ok, signature} = CloudKMS.sign("test", cred, "project", "location", "keychain", "key", "version")
      assert signature == Curvy.Signature.parse(@signature_der)
      assert :meck.num_calls(Goth, :fetch!, [cred]) == 1
    end
  end

  defp stub_goth_fetch!(name) do
    cred = {:goth_credential, name}

    :meck.expect(Goth, :fetch!, fn ^cred -> %{token: "stubbed-token", type: "Bearer"} end)
    cred
  end
end

import Config

config :cartouche, :chain_id, :goerli
config :cartouche, :client, Cartouche.Test.Client
config :cartouche, :open_chain_base_url, "https://example.com/open-chain"
config :cartouche, :open_chain_client, Cartouche.OpenChainTest.TestClient
config :cartouche, :signer, default: {:priv_key, <<1::256>>}

config :tesla, adapter: Tesla.Mock

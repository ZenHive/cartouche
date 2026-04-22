import Config

config :tesla, adapter: Tesla.Mock
config :cartouche, :client, Cartouche.Test.Client
config :cartouche, :open_chain_client, Cartouche.OpenChainTest.TestClient
config :cartouche, :open_chain_base_url, "https://example.com/open-chain"
config :cartouche, :chain_id, :goerli
config :cartouche, :signer, default: {:priv_key, <<1::256>>}

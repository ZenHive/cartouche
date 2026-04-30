defmodule Cartouche.Test.Live do
  @moduledoc """
  Helpers for the mainnet archive integration suite.

  Tests pass `live_opts()` as the keyword list to every
  `Cartouche.RPC.*` call. The opts include `client: Finch` (bypassing the
  test-env mock per-call) and `ethereum_node: <url>` (overriding the
  default). No Application env mutation, no `on_exit` cleanup needed.

      test "eth_chainId returns 1" do
        assert {:ok, 1} = Cartouche.RPC.eth_chain_id(live_opts())
      end

  Override the URL with `CARTOUCHE_LIVE_NODE_URL`.
  """
  import ExUnit.Assertions

  @default_url "http://127.0.0.1:8545"

  @spec live_rpc_url() :: String.t()
  def live_rpc_url, do: System.get_env("CARTOUCHE_LIVE_NODE_URL", @default_url)

  @spec live_opts() :: Keyword.t()
  def live_opts, do: [client: Finch, ethereum_node: live_rpc_url(), timeout: 30_000]

  @spec assert_node_available!() :: :ok | no_return()
  def assert_node_available! do
    case Cartouche.RPC.eth_chain_id(live_opts()) do
      {:ok, 1} ->
        :ok

      {:ok, other} ->
        flunk("""
        Integration node at #{live_rpc_url()} reported chain_id=#{other}, expected 1 (Ethereum mainnet).
        This suite pins mainnet historical anchors. Connect to a mainnet archive node.
        """)

      {:error, reason} ->
        flunk("""
        Integration test opt-in detected (mix integration / mix test --include integration)
        but the Ethereum mainnet archive node is unreachable.

        Expected node at: #{live_rpc_url()}
        Error: #{inspect(reason)}

        Start the SSH tunnel:

            ssh -L 8545:127.0.0.1:8545 -L 8546:127.0.0.1:8546 blockwatch-one

        Override the URL via env var:

            export CARTOUCHE_LIVE_NODE_URL=http://your-node:8545

        Then re-run:

            mix integration
        """)
    end
  end
end

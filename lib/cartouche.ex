defmodule Cartouche do
  @moduledoc """
  Cartouche is an attributed fork of
  [hayesgm/signet](https://github.com/hayesgm/signet) — an Ethereum key
  manager and RPC client for Elixir, maintained by
  [ZenHive](https://github.com/ZenHive).

  This is the `0.0.1` placeholder release that claims the hex namespace.
  Active development lands in `0.1.x`, which ports the signet codebase
  under the `Cartouche` module tree.

  See the project `README.md` and `CHANGELOG.md` for the relationship to
  upstream signet and the attribution details.
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the compile-time version string of the cartouche package.

  ## Examples

      iex> is_binary(Cartouche.version())
      true

  """
  @spec version() :: String.t()
  def version, do: @version
end

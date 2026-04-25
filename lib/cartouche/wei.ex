defmodule Cartouche.Wei do
  @moduledoc """
  Conversions between Ethereum denominations and wei.
  """

  @doc ~S"""
  Converts a number to wei, possibly from gwei, etc.

  ## Examples

      iex> Cartouche.Wei.to_wei(100)
      100

      iex> Cartouche.Wei.to_wei({100, :gwei})
      100000000000
  """
  @spec to_wei(integer() | {integer(), :wei | :gwei}) :: integer()
  def to_wei(amount) when is_integer(amount), do: amount
  def to_wei({amount, :wei}) when is_integer(amount), do: amount
  def to_wei({amount, :gwei}) when is_integer(amount), do: amount * 1_000_000_000
end

defmodule Cartouche.Wei do
  @moduledoc """
  Conversions between Ethereum denominations and wei.

  Supports bare non-negative integer inputs (treated as wei), integer `:wei`,
  integer `:gwei`, and integer or `Decimal` `:eth` inputs. `:eth` is the only
  ETH-denomination atom accepted; `:ether` is not supported so callers use the
  same short form as `:wei` and `:gwei`.
  """

  @wei_per_gwei 1_000_000_000
  @wei_per_eth 1_000_000_000_000_000_000
  @decimal_wei_per_eth Decimal.new(@wei_per_eth)

  @doc ~S"""
  Converts a number to wei, possibly from gwei or eth.

  ## Examples

      iex> Cartouche.Wei.to_wei(100)
      100

      iex> Cartouche.Wei.to_wei({100, :gwei})
      100000000000

      iex> Cartouche.Wei.to_wei({1, :eth})
      1000000000000000000
  """
  @spec to_wei(non_neg_integer() | {non_neg_integer(), :wei | :gwei | :eth} | {Decimal.t(), :eth}) ::
          non_neg_integer()
  def to_wei(amount) when is_integer(amount) and amount >= 0, do: amount
  def to_wei({amount, :wei}) when is_integer(amount) and amount >= 0, do: amount
  def to_wei({amount, :gwei}) when is_integer(amount) and amount >= 0, do: amount * @wei_per_gwei
  def to_wei({amount, :eth}) when is_integer(amount) and amount >= 0, do: amount * @wei_per_eth

  def to_wei({%Decimal{} = amount, :eth}) do
    if Decimal.compare(amount, 0) == :lt do
      raise ArgumentError, "cannot convert negative eth amount to wei"
    end

    amount
    |> Decimal.mult(@decimal_wei_per_eth)
    |> Decimal.to_integer()
  end
end

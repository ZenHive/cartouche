defmodule Cartouche.RecoveryBit do
  @moduledoc """
  There are a number of ways to look at recovery bits. Either:

  * `:base`: In the range `{0,1}`, which are the outputs of a signer library
  * `:ethereum`: In the range `{27,28}`, as defined in the yellow paper
  * `:eip155`: In the range `{35+chain_id*2,35+chain_id*2+1}`, as defined in EIP-155

  This module provides tools between switching through these choices.
  """

  @rec_types [:base, :ethereum, :eip155]
  @type rec_type() :: :base | :ethereum | :eip155

  @doc """
  Normalizes a binary-encoded signature to the given requested type,
  i.e. `:base`, `:ethereum`, or `:eip155`.

  ## Examples

      iex> Cartouche.RecoveryBit.normalize(28, :eip155)
      46

      iex> Cartouche.RecoveryBit.normalize(1, :ethereum)
      28

      iex> Cartouche.RecoveryBit.normalize(45, :base)
      0
  """
  @spec normalize(non_neg_integer(), rec_type()) :: non_neg_integer() | no_return()
  def normalize(recovery_bit, rec_type \\ :eip155) when rec_type in @rec_types do
    base = recover_base(recovery_bit)

    case rec_type do
      :base ->
        base

      :ethereum ->
        base + 27

      :eip155 ->
        35 + Cartouche.Application.chain_id() * 2 + base
    end
  end

  @doc """
  Normalizes a binary-encoded signature to the given requested type,
  i.e. `:base`, `:ethereum`, or `:eip155`.

  ## Examples

      iex> Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 28>>, :eip155)
      <<1::256, 2::256, 46>>

      iex> Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 1>>, :ethereum)
      <<1::256, 2::256, 28>>

      iex> Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 45>>, :base)
      <<1::256, 2::256, 0>>
  """
  @spec normalize_signature(Cartouche.signature(), rec_type()) :: Cartouche.signature() | no_return()
  def normalize_signature(<<rs::binary-size(64), v>>, rec_type \\ :eip155) when rec_type in @rec_types do
    v_normalized = normalize(v, rec_type)

    <<rs::binary-size(64), v_normalized::8>>
  end

  @doc """
  Normalizes a recovery bit to be either 0 or 1.

  ## Examples

      iex> Cartouche.RecoveryBit.recover_base(0)
      0

      iex> Cartouche.RecoveryBit.recover_base(1)
      1

      iex> Cartouche.RecoveryBit.recover_base(27)
      0

      iex> Cartouche.RecoveryBit.recover_base(28)
      1

      iex> Cartouche.RecoveryBit.recover_base(45)
      0

      iex> Cartouche.RecoveryBit.recover_base(46)
      1

      iex> Cartouche.RecoveryBit.recover_base(47)
      ** (RuntimeError) Invalid EIP-155 Signature: recovery_bit=47, chain_id=5

      iex> Cartouche.RecoveryBit.recover_base(2)
      ** (FunctionClauseError) no function clause matching in Cartouche.RecoveryBit.recover_base/1
  """
  @spec recover_base(non_neg_integer()) :: 0 | 1 | no_return()
  def recover_base(v) when v in [0, 1], do: v
  def recover_base(v) when v in [27, 28], do: v - 27

  def recover_base(v) when v >= 35 do
    case v - Cartouche.Application.chain_id() * 2 - 35 do
      base when base in [0, 1] ->
        base

      _ ->
        raise "Invalid EIP-155 Signature: recovery_bit=#{v}, chain_id=#{Cartouche.Application.chain_id()}"
    end
  end
end

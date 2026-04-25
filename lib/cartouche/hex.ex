defmodule Cartouche.Hex do
  @moduledoc """
  Helper module for parsing and encoding hex values.

  If you `use Cartouche.Hex`, then you can use the `~h` sigil for compile-time
  hex-to-binary compilation.
  """

  defmodule HexError do
    @moduledoc false
    defexception message: "invalid hex"
  end

  @type t :: binary()

  defmacro __using__(_opts) do
    quote do
      import Cartouche.Hex,
        only: [sigil_h: 2, hex!: 1, to_hex: 1, to_address: 1, from_hex: 1, from_hex!: 1]

      alias Cartouche.Hex

      require Hex
    end
  end

  @doc ~S"""
  Handles the sigil `~h` for list of words.

  Parses a hex string at compile-time.

  ## Examples

      iex> use Cartouche.Hex
      iex> ~h[0x22]
      <<0x22>>

      iex> use Cartouche.Hex
      iex> ~h[0x2244]
      <<0x22, 0x44>>
  """
  defmacro sigil_h(term, modifiers)

  defmacro sigil_h({:<<>>, _meta, [string]}, _modifiers = []) when is_binary(string) do
    hex_str = :elixir_interpolation.unescape_string(string)

    Cartouche.Hex.decode_hex!(hex_str)
  end

  @doc ~S"""
  Similar non-sigil compile-time hex parser.

  ## Examples

      iex> use Cartouche.Hex
      iex> hex!("0x22")
      <<0x22>>

      iex> use Cartouche.Hex
      iex> hex!("0x2244")
      <<0x22, 0x44>>
  """
  defmacro hex!(hex_str) when is_binary(hex_str) do
    Cartouche.Hex.decode_hex!(hex_str)
  end

  @doc """
  Parses a hex string, but returns `:error` instead
  of raising if hex is invalid.

  ## Examples

      iex> Cartouche.Hex.decode_hex("0xaabb")
      {:ok, <<170, 187>>}

      iex> Cartouche.Hex.decode_hex("aabb")
      {:ok, <<170, 187>>}

      iex> Cartouche.Hex.decode_hex("0xgggg")
      :invalid_hex
  """
  @spec decode_hex(String.t()) :: {:ok, t()} | :error
  def decode_hex(b), do: decode_hex_(b)

  @doc """
  Alias for `decode_hex`.

  ## Examples

      iex> Cartouche.Hex.from_hex("0xaabb")
      {:ok, <<0xaa, 0xbb>>}
  """
  @spec from_hex(t()) :: String.t()
  def from_hex(b), do: decode_hex(b)

  @doc """
  Alias for `decode_hex!`.

  ## Examples

    iex> Cartouche.Hex.from_hex!("0xaabb")
    <<0xaa, 0xbb>>
  """
  @spec from_hex!(t()) :: String.t()
  def from_hex!(b), do: decode_hex!(b)

  @doc """
  Parses a hex string and raises if invalid.

  ## Examples

    iex> Cartouche.Hex.decode_hex!("aabb")
    <<170, 187>>

    iex> Cartouche.Hex.decode_hex!("0xggaabb")
    ** (Cartouche.Hex.HexError) invalid hex: "0xggaabb"
  """
  @spec decode_hex!(String.t()) :: t()
  def decode_hex!(b) do
    case decode_hex_(b) do
      {:ok, hex} ->
        hex

      _ ->
        raise HexError, "invalid hex: \"#{b}\""
    end
  end

  @doc """
  Parses an Ethereum 20-bytes hex string.

  Identical to `decode_hex!/1` except fails if
  string is not exactly 20-bytes.

  ## Examples

    iex> Cartouche.Hex.decode_address!("0x0000000000000000000000000000000000000001")
    <<1::160>>

    iex> Cartouche.Hex.decode_address!("0xaabb")
    ** (Cartouche.Hex.HexError) invalid hex address: "0xaabb"
  """
  @spec decode_address!(String.t()) :: t() | no_return()
  def decode_address!(hex) do
    decode_sized!(hex, 20, "invalid hex address")
  end

  @doc """
  Parses an Ethereum 32-bytes hex string.

  Identical to `decode_hex!/1` except fails if
  string is not exactly 32-bytes.

  ## Examples

    iex> Cartouche.Hex.decode_word!("0x0000000000000000000000000000000000000000000000000000000000000001")
    <<1::256>>

    iex> Cartouche.Hex.decode_word!("0xaabb")
    ** (Cartouche.Hex.HexError) invalid hex word: "0xaabb"
  """
  @spec decode_word!(String.t()) :: t() | no_return()
  def decode_word!(hex) do
    decode_sized!(hex, 32, "invalid hex word")
  end

  @doc """
  Parses an Ethereum x-bytes hex string.

  Identical to `decode_hex!/1` except fails if
  string is not exactly x-bytes.

  ## Examples

    iex> Cartouche.Hex.decode_sized!("0x001122", 3)
    <<0x00, 0x11, 0x22>>

    iex> Cartouche.Hex.decode_sized!("0xaabb", 3)
    ** (Cartouche.Hex.HexError) invalid 3-byte sized hex: "0xaabb"
  """
  @spec decode_sized!(String.t(), integer(), String.t() | nil) :: t() | no_return()
  def decode_sized!(hex, sz, msg \\ nil) do
    res = decode_hex!(hex)

    if byte_size(res) == sz do
      res
    else
      raise HexError,
            (case msg do
               nil ->
                 "invalid #{sz}-byte sized hex: \"#{hex}\""

               _ ->
                 "#{msg}: \"#{hex}\""
             end)
    end
  end

  @doc """
  Parses hex is value is not nil, otherwise returns `nil`.

  ## Examples

    iex> Cartouche.Hex.decode_maybe_hex!("0xaabb")
    <<170, 187>>

    iex> Cartouche.Hex.decode_maybe_hex!(nil)
    nil
  """
  @spec decode_maybe_hex!(String.t() | nil) :: t() | nil
  def decode_maybe_hex!(h) when is_nil(h), do: nil
  def decode_maybe_hex!(h) when is_binary(h), do: decode_hex!(h)

  @doc """
  Parses hex value as a big-endian integer. Raises if invalid.

  ## Examples

    iex> Cartouche.Hex.decode_hex_number!("0xaabb")
    0xaabb

    iex> Cartouche.Hex.decode_hex_number!("0xgggg")
    ** (Cartouche.Hex.HexError) invalid hex number: "0xgggg"
  """
  @spec decode_hex_number!(String.t()) :: integer() | no_return()
  def decode_hex_number!(b) do
    case decode_hex_number(b) do
      {:ok, x} ->
        x

      :invalid_hex ->
        raise HexError, "invalid hex number: \"#{b}\""
    end
  end

  @doc ~S"""
  Decodes hex, allowing it to either be `"0x..."` or a raw binary.

  Note: a hex-printed string, in this case, must start with `0x`,
        otherwise it will be interpreted as its ASCII values.

  ## Examples

      iex> Cartouche.Hex.decode_hex_input!("0x55")
      <<0x55>>

      iex> Cartouche.Hex.decode_hex_input!(<<0x55>>)
      <<0x55>>
  """
  @spec decode_hex_input!(String.t() | binary()) :: t()
  def decode_hex_input!("0x" <> _ = hex), do: decode_hex!(hex)
  def decode_hex_input!(hex) when is_binary(hex), do: hex

  @doc """
  Parses hex value as a big-endian integer.

  ## Examples

      iex> Cartouche.Hex.decode_hex_number("0xaabb")
      {:ok, 0xaabb}

      iex> Cartouche.Hex.decode_hex_number("0xgggg")
      :invalid_hex
  """
  @spec decode_hex_number(String.t()) :: {:ok, integer()} | :error
  def decode_hex_number(b) do
    with {:ok, x} <- decode_hex(b), do: {:ok, :binary.decode_unsigned(x)}
  end

  @doc """
  Encodes a given value as a lowercase hex string, starting with `0x`.

  ## Examples

    iex> Cartouche.Hex.encode_hex(<<0xaa, 0xbb>>)
    "0xaabb"
  """
  @spec encode_hex(t()) :: String.t()
  def encode_hex(b) when is_binary(b), do: "0x" <> Base.encode16(b, case: :lower)

  @doc """
  Alias for `encode_hex`.

  ## Examples

    iex> Cartouche.Hex.to_hex(<<0xaa, 0xbb>>)
    "0xaabb"
  """
  @spec to_hex(t()) :: String.t()
  def to_hex(b), do: encode_hex(b)

  @doc ~S"""
  Encodes hex, in CAPITALS.

  ## Examples

    iex> Cartouche.Hex.encode_big_hex(<<0xcc, 0xdd>>)
    "0xCCDD"
  """
  @spec encode_big_hex(binary()) :: String.t()
  def encode_big_hex(hex) when is_binary(hex), do: "0x" <> Base.encode16(hex)

  @doc ~S"""
  Encodes hex, striping any leading zeros.

  ## Examples

    iex> Cartouche.Hex.encode_short_hex(<<0xc>>)
    "0xC"

    iex> Cartouche.Hex.encode_short_hex(12)
    "0xC"

    iex> Cartouche.Hex.encode_short_hex(<<0x0>>)
    "0x0"
  """
  @spec encode_short_hex(binary() | integer()) :: String.t()
  def encode_short_hex(hex) when is_binary(hex) do
    enc = Base.encode16(hex)

    "0x" <>
      case String.replace_leading(enc, "0", "") do
        "" ->
          "0"

        els ->
          els
      end
  end

  def encode_short_hex(v) when is_integer(v), do: encode_short_hex(:binary.encode_unsigned(v))

  @doc ~S"""
  Pads a binary to a given length.

  ## Examples

      iex> Cartouche.Hex.pad(<<1, 2>>, 2)
      <<1, 2>>

      iex> Cartouche.Hex.pad(<<1, 2>>, 4)
      <<0, 0, 1, 2>>

      iex> Cartouche.Hex.pad(<<1, 2>>, 1)
      ** (FunctionClauseError) no function clause matching in Cartouche.Hex.pad/2
  """
  @spec pad(binary(), pos_integer()) :: binary()
  def pad(bin, size) when size > byte_size(bin) do
    padding_len_bits = (size - byte_size(bin)) * 8
    <<0::size(padding_len_bits)>> <> bin
  end

  def pad(bin, size) when size == byte_size(bin), do: bin

  @doc ~S"""
  Encodes a number as a binary of a fixed byte length, left-padded with zeros.

  ## Examples

      iex> Cartouche.Hex.encode_bytes(257, 4)
      <<0, 0, 1, 1>>

      iex> Cartouche.Hex.encode_bytes(nil, 4)
      nil
  """
  @spec encode_bytes(integer() | nil, pos_integer()) :: binary() | nil
  def encode_bytes(nil, _), do: nil
  def encode_bytes(b, size), do: pad(:binary.encode_unsigned(b), size)

  @doc ~S"""
  Returns the nibbles of a binary as a list.

  ## Examples

      iex> Cartouche.Hex.nibbles(<<0xF5, 0xE6, 0xD0>>)
      [0xF, 0x5, 0xE, 0x6, 0xD, 0x0]
  """
  @spec nibbles(binary()) :: [0..15]
  def nibbles(v), do: Enum.reverse(do_nibbles(v, []))

  defp do_nibbles(<<>>, acc), do: acc
  defp do_nibbles(<<high::4, low::4, rest::binary>>, acc), do: do_nibbles(rest, [low, high | acc])

  @doc """
  Encodes a binary as a checksummed Ethereum address.

  ## Examples

    iex> Cartouche.Hex.encode_address(<<0xaa, 0xbb, 0xcc, 0::136>>)
    "0xaABbcC0000000000000000000000000000000000"

    iex> Cartouche.Hex.encode_address(<<55>>)
    ** (Cartouche.Hex.HexError) Expected 20-byte address for in `Cartouche.Hex.encode_address/1`
  """
  @spec encode_address(t()) :: String.t()
  def encode_address(<<_::160>> = b), do: checksum_address(encode_hex(b))

  def encode_address(_), do: raise(HexError, "Expected 20-byte address for in `Cartouche.Hex.encode_address/1`")

  @doc ~S"""
  Checksums an Ethereum address per [EIP-55](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md).

  The result is a string-encoded (mixed-case) version of the address.

  ## Examples

      iex> Cartouche.Hex.checksum_address("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
      "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

      iex> Cartouche.Hex.checksum_address("0xFB6916095CA1DF60BB79CE92CE3EA74C37C5D359")
      "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"

      iex> Cartouche.Hex.checksum_address("0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb")
      "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB"

      iex> Cartouche.Hex.checksum_address("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb")
      "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"
  """
  @spec checksum_address(String.t() | <<_::160>>) :: String.t()
  def checksum_address("0x" <> _ = address) when byte_size(address) == 42, do: checksum_address(decode_hex!(address))

  def checksum_address(address) when is_binary(address) and byte_size(address) == 20 do
    # EIP-55 hashes the *string* form of the address, then cases each nibble
    # of the address based on the matching nibble of the hash.
    "0x" <> address_enc = encode_big_hex(address)
    hash = Cartouche.Hash.keccak(String.downcase(address_enc))

    lower = ~c"0123456789abcdef"
    upper = ~c"0123456789ABCDEF"

    res =
      for {nibble, hash_val} <- Enum.zip(nibbles(address), nibbles(hash)), into: [] do
        casing = if hash_val >= 8, do: upper, else: lower
        Enum.at(casing, nibble)
      end

    "0x" <> to_string(res)
  end

  @doc """
  Alias for `encode_address`.

  ## Examples

    iex> Cartouche.Hex.to_address(<<0xaa, 0xbb, 0xcc, 0::136>>)
    "0xaABbcC0000000000000000000000000000000000"
  """
  @spec to_address(t()) :: String.t()
  def to_address(b), do: encode_address(b)

  @doc """
  If input is a tuple `{:ok, x}` then returns a tuple `{:ok, hex}`
  where `hex = encode(x)`. Otherwise, returns its input unchanged.

  ## Examples

      iex> Cartouche.Hex.encode_hex_result({:ok, <<0xaa, 0xbb>>})
      {:ok, "0xaabb"}

      iex> Cartouche.Hex.encode_hex_result({:error, 55})
      {:error, 55}
  """
  @spec encode_hex_result({:ok, t()} | term()) :: {:ok, String.t()} | term()
  def encode_hex_result({:ok, b}) when is_binary(b), do: {:ok, encode_hex(b)}
  def encode_hex_result(els), do: els

  @doc """
  If input is non-`nil`, returns input encoded as a hex string. Otherwise,
  returns `nil`.

  ## Examples

    iex> Cartouche.Hex.maybe_encode_hex(<<0xaa, 0xbb>>)
    "0xaabb"

    iex> Cartouche.Hex.maybe_encode_hex(nil)
    nil
  """
  @spec maybe_encode_hex(t() | nil) :: String.t() | nil
  def maybe_encode_hex(b) when is_nil(b), do: nil
  def maybe_encode_hex(b) when is_binary(b), do: encode_hex(b)

  # Core function to decode hex
  @spec decode_hex_(String.t()) :: {:ok, t()} | :error
  defp decode_hex_("0x" <> b) when is_binary(b), do: decode_hex_(b)

  defp decode_hex_(b) when is_binary(b) do
    hex_padded =
      if rem(byte_size(b), 2) == 1 do
        "0" <> b
      else
        b
      end

    case Base.decode16(hex_padded, case: :mixed) do
      {:ok, _} = res ->
        res

      :error ->
        :invalid_hex
    end
  end

  @doc false
  def deep_encode_binaries(x) when is_binary(x), do: to_hex(x)
  def deep_encode_binaries(l) when is_list(l), do: Enum.map(l, &deep_encode_binaries/1)

  def deep_encode_binaries(t) when is_tuple(t), do: List.to_tuple(Enum.map(Tuple.to_list(t), &deep_encode_binaries/1))

  def deep_encode_binaries(els), do: els
end

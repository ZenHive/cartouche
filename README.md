# Cartouche

[![Hex.pm](https://img.shields.io/hexpm/v/cartouche.svg)](https://hex.pm/packages/cartouche)

Ethereum key manager and RPC client for Elixir. Cartouche is an **attributed fork** of [hayesgm/signet](https://github.com/hayesgm/signet) maintained by [ZenHive](https://github.com/ZenHive).

## Status

**`0.0.1` — placeholder release.** This version claims the hex namespace. Active development lands in `0.1.x`, which ports the signet codebase under the `Cartouche` module tree.

## Installation

Not recommended yet. Use [`signet`](https://hex.pm/packages/signet) until `0.1.0` ships.

When `0.1.x` is out:

```elixir
def deps do
  [
    {:cartouche, "~> 0.1"}
  ]
end
```

## Relationship to upstream

Cartouche is a fork of `hayesgm/signet`. We upstream fixes where it makes sense. Attribution to the original maintainer (Geoffrey Hayes, Compound Labs) is preserved in `LICENSE` and `CHANGELOG.md`.

## License

MIT. See `LICENSE`.

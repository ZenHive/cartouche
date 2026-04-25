# Cartouche

[![Hex.pm](https://img.shields.io/hexpm/v/cartouche.svg)](https://hex.pm/packages/cartouche)

Ethereum key manager and RPC client for Elixir. Cartouche is an **attributed fork** of [hayesgm/signet](https://github.com/hayesgm/signet) maintained by [ZenHive](https://github.com/ZenHive).

## Status

**`0.1.0` — first active release.** Ports the signet codebase under the `Cartouche` module tree. Active development continues in `0.1.x`; see [CHANGELOG.md](CHANGELOG.md) for what has shipped.

## Installation

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

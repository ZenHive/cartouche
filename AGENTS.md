# Cartouche Development

## Cursor Cloud specific instructions

### Runtime

- **Erlang/OTP 27** installed at `/usr/local/bin/erl` via prebuilt `.deb` from [benoitc/erlang-dist](https://github.com/benoitc/erlang-dist).
- **Elixir 1.18.4** installed at `/usr/local/elixir/bin/`. Ensure `export PATH="/usr/local/elixir/bin:$PATH"` is set before running any Mix commands.
- If `asdf` shims are present in PATH, they will intercept `erl` and fail. The update script removes them; if you see `"No version is set for command erl"`, remove asdf entries from `~/.bashrc` and restart your shell.

### Project overview

Cartouche is a pure Elixir library (no Phoenix, no database, no Docker). It provides Ethereum and Solana JSON-RPC clients, signers, transaction builders, and contract codegen.

### Key commands

| Task | Command |
|------|---------|
| Fetch deps | `mix deps.get` |
| Compile | `mix compile` |
| Run tests | `mix test` |
| Lint (Credo) | `mix credo` |
| Format check | `mix format --check-formatted` |
| Dialyzer | `mix dialyzer` |
| Integration tests | `mix integration` (requires `CARTOUCHE_LIVE_NODE_URL` env var pointing to an Ethereum archive node) |

### Testing notes

- All unit tests use mocked HTTP clients (`Cartouche.Test.Client` and `Cartouche.Solana.Test.Client`). No external services are needed.
- Integration tests are excluded by default (`--exclude integration` tag). Run them via `mix integration` only when an Ethereum archive node is available.
- The test suite runs ~500 tests in ~3 seconds.

### Gotchas

- Credo reports TODO tags as design suggestions (exit code 2) — this is expected, not an error.
- `mix format --check-formatted` may flag pre-existing formatting issues in the repo. These are not blocking for test runs.

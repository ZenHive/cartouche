# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0] — 2026-04-25

First active release under the `cartouche` namespace. Ports the signet codebase under the `Cartouche` module tree with Elixir 1.20 compatibility, a published-on-hex ABI dep (`hieroglyph`), and a cleaned-up dialyzer baseline.

### Changed

- Reset `mix.exs` version from the inherited signet pin `1.6.1` to `0.1.0-dev` ahead of the first hex publish under the `cartouche` namespace (ROADMAP Phase 0, Task 1).
- Swap the `:abi` path dep (`path: "../abi", override: true`) for the published hex package `{:hieroglyph, "~> 1.0", override: true}`. ZenHive's `abi` fork is now on hex.pm as `hieroglyph 1.0.0`; hex package name is `hieroglyph` but the Elixir module namespace remains `ABI`, so no callsite changes. Unblocks `mix hex.publish` for cartouche, which rejects path/git deps (ROADMAP Phase 0, Task 6).
- Update `mix.exs` `:package` for the publish cut: `maintainers: ["ZenHive"]` (was `["Geoffrey Hayes"]` — attribution preserved in `LICENSE` and in `[0.0.1]` below); drop `test/support` from `:files` (test helpers aren't part of the public surface), add `CHANGELOG*`; add `CHANGELOG.md` to `docs[:extras]` so hexdocs renders the release history; add a `Changelog` entry to `package[:links]`.

### Fixed

- Pin bitstring size variables in binary matches across `Cartouche.Solana.Transaction.read_instructions/3`, `Cartouche.Assembly.disassemble_opcode/1`, and `Cartouche.VM.{Memory,Operations}` / `Cartouche.VM.static_call/1` for Elixir 1.20 compatibility. Behaviour-preserving; resolves all `variable "X" is accessed inside size(...) ... must precede it with the pin operator` warnings under 1.20-rc.4 (cleanup.md C1).
- Pin bitstring size variable in `Cartouche.VmTestHelpers.word/2` (`test/support/vm_test_helpers.ex:11`) — missed in the initial C1 sweep; same Elixir 1.20 compat fix.
- Remove leading-underscore on `expected` in `Cartouche.Solana.PDATest` `"wrong bump"` test (`test/solana/pda_test.exs:137`) — variable is used inside the `match?/2` guard at line 143, so the underscore was misleading and fired an Elixir 1.20 warning.
- Cut dialyzer noise floor from 6,620 to 1,626 warnings by fixing typespecs in the upstream `:abi` library. Root cause was that `ABI.encode/2`, `ABI.decode/2-3`, `ABI.decode_event/3-4`, `ABI.TypeEncoder.encode/2`, and `ABI.TypeDecoder.decode_raw/3` lacked `@spec` declarations, and `ABI.FunctionSelector.t()` declared `returns: type` (singular) while the runtime and ABI's own doctests use `returns: [argument_type]`. Dialyzer's inferred success typing for `ABI.encode/2` collapsed the struct branch to `function: nil, types: []` only, so every populated selector at every cartouche callsite was flagged as `will never return`, cascading through `lib/cartouche/contract/i_console.ex`. Fixed in the `zenhive/abi` fork and published to hex.pm as `hieroglyph 1.0.0` (hex package name only; `ABI` module namespace preserved). cartouche consumes the patched library via `{:hieroglyph, "~> 1.0", override: true}` (see `### Changed` above). ABI typespec fixes will be upstreamed via PR to `poanetwork/ex_abi`. (cleanup.md A1+A2; residual cascade tracked under follow-up A1b.)
- Restore `Cartouche.Signer` `@moduledoc` (was `@moduledoc false` with module-level prose stuck in a `@doc` that collided with `start_link/1`'s `@doc`). Eliminates the last compile warning under Elixir 1.20-rc.4 and aligns with cleanup.md's documentation policy (avoid `@moduledoc false`).

### Documentation

- Correct `DEV.md` Sleuth regeneration command — the canonical ABI source is `./priv/Sleuth.json` (vendored), not the previously documented `../sleuth/out/Sleuth.sol/Sleuth.json` external path.

## [0.0.1] — 2026-04-22

Initial placeholder release. Claims the `cartouche` hex namespace under ZenHive ownership.

Active development (fork of `hayesgm/signet`) lands in `0.1.x`.

### Attribution

Cartouche is an attributed fork of [hayesgm/signet](https://github.com/hayesgm/signet), originally authored by Geoffrey Hayes at Compound Labs, Inc. (2022). The upstream MIT license is preserved alongside the ZenHive copyright in `LICENSE`.

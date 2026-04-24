# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- Pin bitstring size variables in binary matches across `Cartouche.Solana.Transaction.read_instructions/3`, `Cartouche.Assembly.disassemble_opcode/1`, and `Cartouche.VM.{Memory,Operations}` / `Cartouche.VM.static_call/1` for Elixir 1.20 compatibility. Behaviour-preserving; resolves all `variable "X" is accessed inside size(...) ... must precede it with the pin operator` warnings under 1.20-rc.4 (cleanup.md C1).
- Cut dialyzer noise floor from 6,620 to 1,626 warnings by fixing typespecs in the upstream `:abi` library. Root cause was that `ABI.encode/2`, `ABI.decode/2-3`, `ABI.decode_event/3-4`, `ABI.TypeEncoder.encode/2`, and `ABI.TypeDecoder.decode_raw/3` lacked `@spec` declarations, and `ABI.FunctionSelector.t()` declared `returns: type` (singular) while the runtime and ABI's own doctests use `returns: [argument_type]`. Dialyzer's inferred success typing for `ABI.encode/2` collapsed the struct branch to `function: nil, types: []` only, so every populated selector at every cartouche callsite was flagged as `will never return`, cascading through `lib/cartouche/contract/i_console.ex`. Fixed in the `zenhive/abi` fork; cartouche switched from `{:abi, "~> 1.3.0"}` to `{:abi, path: "../abi", override: true}` to consume the patched library. ABI typespec fixes will be upstreamed via PR. (cleanup.md A1+A2; residual cascade tracked under follow-up A1b.)
- Restore `Cartouche.Signer` `@moduledoc` (was `@moduledoc false` with module-level prose stuck in a `@doc` that collided with `start_link/1`'s `@doc`). Eliminates the last compile warning under Elixir 1.20-rc.4 and aligns with cleanup.md's documentation policy (avoid `@moduledoc false`).

### Documentation

- Correct `DEV.md` Sleuth regeneration command — the canonical ABI source is `./priv/Sleuth.json` (vendored), not the previously documented `../sleuth/out/Sleuth.sol/Sleuth.json` external path.

## [0.0.1] — 2026-04-22

Initial placeholder release. Claims the `cartouche` hex namespace under ZenHive ownership.

Active development (fork of `hayesgm/signet`) lands in `0.1.x`.

### Attribution

Cartouche is an attributed fork of [hayesgm/signet](https://github.com/hayesgm/signet), originally authored by Geoffrey Hayes at Compound Labs, Inc. (2022). The upstream MIT license is preserved alongside the ZenHive copyright in `LICENSE`.

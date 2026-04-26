# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- Generator gates `exec_vm_*` emission on real bytecode. `Mix.Tasks.Cartouche.Gen` now treats `nil`, blank strings, `"0x"`, and `"0x" <> whitespace` as missing bytecode (new `blank_bytecode?/1` predicate in `lib/mix/cartouche.gen.ex`), and the `:pure` dispatch branch now requires `has_bytecode` before emitting `exec_vm_fn` / `exec_vm_raw_fn`. Without both, the generator was emitting `def bytecode, do: hex!("0x")` (compile-time `<<>>`) plus a `:pure` branch that always emitted `exec_vm_*` — producing 762 `exec_vm_*` functions in `Cartouche.Contract.IConsole` (Hardhat console.log interface, no on-chain bytecode) that called `Cartouche.VM.exec_call(<<>>, ...)` and always raised `VmError`. Dialyzer flagged each as `no_return`, cascading to 1534 of 1626 total warnings. New regression tests in `test/mix/cartouche_gen_test.exs` cover the four blank-bytecode shapes plus the working real-bytecode path. Drops `Cartouche.Contract.IConsole.{bytecode/0, deployed_bytecode/0, exec_vm_*}` from the generated module (RPC-side `encode_*` / `call_*` / `execute_*` family preserved); regenerated file is 18705 lines (was 28084). Bundled with the bug fix: the four pre-existing credo issues in `lib/mix/cartouche.gen.ex` (L153 nesting in `rename_dups/1`, L170 cyclomatic in `get_encode_calls/2`, L247 cyclomatic in `encode_function_call/3`, L337 nesting) are resolved by extracting `accumulate_named_abi/2` + `dedup_named_abi/5` + `maybe_rename_dup_fn/5` (rename-dups), `merge_encode_call_result/2` (encode-calls reducer), and ~16 `build_*_fn/1` helpers + `select_emitted_fns/3` + supporting argument-spec helpers (encode-function dispatch). Generator output AST is byte-identical to pre-refactor for `i_console.ex` (verified via the new `cartouche_gen_test.exs` suite). One additional post-process: `strip_zero_arity_def_parens/1` rewrites `def name()` → `def name` on emitted defs (the macro source must keep the parens — `def unquote(name)()` is the canonical AST shape; without parens, `unquote(:foo)` produces a literal-atom AST and won't compile), eliminating ~382 `ParenthesesOnZeroArityDefs` flags from generated `i_console.ex` without manual annotation. `String.to_atom/1` callsites in 6 generator helpers carry `# sobelow_skip ["DOS.StringToAtom"]` annotations (build-time codegen, not runtime input).
- Delete `Cartouche.Util` grab-bag module. Helpers redistributed into five focused modules: `Cartouche.Address.from_public_key/1` (renamed from `Util.get_eth_address/1`), `Cartouche.Chain.parse_id/1` + chain registry (renamed from `Util.parse_chain_id/1`), `Cartouche.Wei.to_wei/1`, `Cartouche.HTTP.normalize_finch_result/1`, and `Cartouche.RecoveryBit` (promoted from the nested `Cartouche.Util.RecoveryBit` submodule). The five hex helpers `decode_hex_input!/1`, `encode_bytes/2`, `pad/2`, `nibbles/1`, and `checksum_address/1` move to `Cartouche.Hex`. The seven `@deprecated` decode/encode aliases (`decode_hex/1`, `decode_hex!/1`, `decode_sized_hex!/2`, `decode_word!/1`, `decode_address!/1`, `decode_hex_number!/1`, `encode_hex/2`) and the `keccak/1` defdelegate are removed — modern equivalents already exist in `Cartouche.Hex` / `Cartouche.Hash`. `nil_map/2` is inlined as a module-local private helper in `Cartouche.Trace` and `Cartouche.Trace.Action` (its only consumers).

### Fixed

- `Cartouche.RecoveryBit.normalize/2` and `normalize_signature/2` specs: literal atom `:no_return` replaced with the `no_return()` type (ROADMAP Phase 1.1). Dialyzer silently accepts unknown atoms in unions, so this was semantically meaningless; now matches the documented raise behaviour.

## [0.1.0] — 2026-04-25

First active release under the `cartouche` namespace. Ports the signet codebase under the `Cartouche` module tree with Elixir 1.20 compatibility, a published-on-hex ABI dep (`hieroglyph`), and a cleaned-up dialyzer baseline.

### Changed

- Reset `mix.exs` version from the inherited signet pin `1.6.1` to `0.1.0-dev` ahead of the first hex publish under the `cartouche` namespace (ROADMAP Phase 0, Task 1).
- Swap the `:abi` path dep (`path: "../abi", override: true`) for the published hex package `{:hieroglyph, "~> 1.0", override: true}`. ZenHive's `abi` fork is now on hex.pm as `hieroglyph 1.0.0`; hex package name is `hieroglyph` but the Elixir module namespace remains `ABI`, so no callsite changes. Unblocks `mix hex.publish` for cartouche, which rejects path/git deps (ROADMAP Phase 0, Task 6).
- Update `mix.exs` `:package` for the publish cut: `maintainers: ["ZenHive"]` (was `["Geoffrey Hayes"]` — attribution preserved in `LICENSE` and in `[0.0.1]` below); drop `test/support` from `:files` (test helpers aren't part of the public surface), add `CHANGELOG*`; add `CHANGELOG.md` to `docs[:extras]` so hexdocs renders the release history; add a `Changelog` entry to `package[:links]`.

### Fixed

- Pin bitstring size variables in binary matches across `Cartouche.Solana.Transaction.read_instructions`, `Cartouche.Assembly.disassemble_opcode/1`, and `Cartouche.VM.{Memory,Operations}` / `Cartouche.VM.static_call` for Elixir 1.20 compatibility. Behaviour-preserving; resolves all `variable "X" is accessed inside size(...) ... must precede it with the pin operator` warnings under 1.20-rc.4 (cleanup.md C1).
- Pin bitstring size variable in `Cartouche.VmTestHelpers.word/2` (`test/support/vm_test_helpers.ex:11`) — missed in the initial C1 sweep; same Elixir 1.20 compat fix.
- Remove leading-underscore on `expected` in `Cartouche.Solana.PDATest` `"wrong bump"` test (`test/solana/pda_test.exs:137`) — variable is used inside the `match?/2` guard at line 143, so the underscore was misleading and fired an Elixir 1.20 warning.
- Cut dialyzer noise floor from 6,620 to 1,626 warnings by fixing typespecs in the upstream `:abi` library. Root cause was that `ABI.encode/2`, `ABI.decode/2-3`, `ABI.decode_event/3-4`, `ABI.TypeEncoder.encode/2`, and `ABI.TypeDecoder.decode_raw/3` lacked `@spec` declarations, and `ABI.FunctionSelector.t()` declared `returns: type` (singular) while the runtime and ABI's own doctests use `returns: [argument_type]`. Dialyzer's inferred success typing for `ABI.encode/2` collapsed the struct branch to `function: nil, types: []` only, so every populated selector at every cartouche callsite was flagged as `will never return`, cascading through `lib/cartouche/contract/i_console.ex`. Fixed in the `zenhive/abi` fork and published to hex.pm as `hieroglyph 1.0.0` (hex package name only; `ABI` module namespace preserved). cartouche consumes the patched library via `{:hieroglyph, "~> 1.0", override: true}` (see `### Changed` above). ABI typespec fixes will be upstreamed via PR to `poanetwork/ex_abi`. (cleanup.md A1+A2; residual cascade tracked under follow-up A1b.)
- Restore `Cartouche.Signer` `@moduledoc` (was `@moduledoc false` with module-level prose stuck in a `@doc` that collided with `start_link/1`'s `@doc`). Eliminates the last compile warning under Elixir 1.20-rc.4 and aligns with cleanup.md's documentation policy (avoid `@moduledoc false`).
- Replace `@moduledoc false` with descriptive `@moduledoc` on six submodules whose `t()` types are referenced from outer public specs: `Cartouche.VM.Input`, `Cartouche.VM.Context`, `Cartouche.VM.ExecutionResult`, `Cartouche.Trace.Action`, `Cartouche.Receipt.Log`, `Cartouche.DebugTrace.StructLog`. Eliminates all "documentation references type X but the module is hidden" warnings from `mix docs`; clean docs build for the publish cut (ROADMAP Task 36).
- IAL/markdown collision in four `Cartouche.Hex` doctest blocks (`decode_hex/1`, `from_hex/1`, `decode_hex_number/1`, `encode_hex_result/1`): bumped doctest source indent from 4 to 6 spaces so the heredoc-stripped output reaches the 4-space code-block threshold instead of being parsed as prose lines starting with `{`.
- Drop `/arity` suffix on private-function references in this CHANGELOG (`Cartouche.Solana.Transaction.read_instructions`, `Cartouche.VM.static_call`) so ex_doc no longer attempts to auto-link non-public functions and emit broken-link warnings.

### Documentation

- Correct `DEV.md` Sleuth regeneration command — the canonical ABI source is `./priv/Sleuth.json` (vendored), not the previously documented `../sleuth/out/Sleuth.sol/Sleuth.json` external path.

## [0.0.1] — 2026-04-22

Initial placeholder release. Claims the `cartouche` hex namespace under ZenHive ownership.

Active development (fork of `hayesgm/signet`) lands in `0.1.x`.

### Attribution

Cartouche is an attributed fork of [hayesgm/signet](https://github.com/hayesgm/signet), originally authored by Geoffrey Hayes at Compound Labs, Inc. (2022). The upstream MIT license is preserved alongside the ZenHive copyright in `LICENSE`.

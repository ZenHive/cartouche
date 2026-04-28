# Cartouche Roadmap

**Vision:** Cartouche is an attributed fork of [`hayesgm/signet`](https://github.com/hayesgm/signet) under ZenHive ownership. Active development happens here. Upstream PRs to `hayesgm/signet` are opened **on-demand** when a fix is clean, self-contained, and independently useful — no SLA either direction. The fork decision and rationale live in [`CHANGELOG.md`](CHANGELOG.md) under `0.0.1`; this document is strictly forward-looking.

**Status legend:** ⬜ pending · 🔄 in progress (name branch) · 🔶 blocked/deferred · ✅ complete

**Scoring:** `[D:n/B:n/U:n → Eff:x]` per `~/.claude/includes/task-prioritization.md`.
- `B` = impact magnitude (onchain `@dialyzer` strips, new feature shipped, blocked work unblocked).
- `U` = unlock leverage for **downstream consumers** — primarily [onchain](../onchain), secondarily any future cartouche user. Scoring is decoupled from upstream-merge likelihood. Upstream-merge considerations live in prose in Phase 10 only.

---

## Scope principle (what belongs here vs. in onchain)

Cartouche = primitives; onchain = application/protocol. Even though cartouche is our own package, keeping the split sharp prevents protocol-layer creep and keeps onchain the right home for RPC wrappers, ERC parsers, and observability.

| In cartouche's scope | In onchain's scope |
|---|---|
| Transaction type encoding (V1, V2, V3 blob, V4 auth-list) | RPC method wrappers (`eth_getProof`, `eth_syncing`, batch requests) |
| Signer internals, key management, CloudKMS | Helpers that compose cartouche structs (fee suggestion on `FeeHistory`) |
| Hex / ABI / typed-data / chain crypto primitives | Protocol parsers (ENS, ERC-20/721/1155, Transfer events) |
| Raw transaction encode **and decode** | Subscription management, Multicall, wallet classification |
| `Cartouche.RPC.send_rpc/3` transport-level concerns | Observability facades (telemetry, retry/backoff wrappers) |

Resist "while we're here, just this once" helpers — they belong in onchain.

### EIP triage rubric

| EIP type | Where | Notes |
|---|---|---|
| Core — new transaction type (4844, 7702, future) | **cartouche** | Modifies `Cartouche.Transaction` encode/sign |
| Core — new signer scheme / crypto primitive | **cartouche** | Primitive layer |
| Interface — new JSON-RPC method | **onchain** | Wrapper over `Cartouche.RPC.send_rpc/3` |
| ERC — contract standard (ERC-20/721/1155/4626/8004/…) | **onchain** or sibling | Pure contract calls; spin a sibling package (`onchain_agents`, `onchain_aave`, …) when domain-heavy |
| Core — new precompile | **onchain** usually | Contract-call wrapper; cartouche only if bespoke encoding required |
| Networking / Meta / Informational | **ignore** | Not a client-library concern |

**Never chase EIPs speculatively.** An EIP enters the roadmap only when a consumer project needs it.

---

## Coverage gate for change tasks

Before any task that mutates an existing module, that module's `mix test.json --cover` percentage must be at the target tier (≥80% standard, ≥95% for crypto / signing / RLP). Task 43 set the precedent: raise coverage *first*, mutate *second*. New tasks that touch sub-target modules MUST include an explicit coverage sub-step or be paired with a preceding coverage task. Coverage on auto-generated modules (`Cartouche.Contract.IConsole`) is not load-bearing — exclude when reading the headline %.

---

## 🎯 Current Focus

**Phase 0 — ship `0.1.0`.** Prep pass complete (Tasks 1–4, 2026-04-24): version at `0.1.0-dev`, 665 tests green, dialyzer inventory matches the pre-rename audit exactly (11/11 `invalid_contract` accounted for), `mix docs` builds cleanly with the cartouche module tree. Publish cut prepared 2026-04-25 (Task 37): version bumped to `0.1.0`, CHANGELOG `[Unreleased]` moved under `[0.1.0] — 2026-04-25`, mix.exs `:package` polished (ZenHive maintainers, test/support dropped from `:files`, CHANGELOG added to docs `:extras` + `:links`), README install section activated. Task 36 closed 2026-04-25 — `mix docs` now emits zero warnings.

The doctor-driven typespec sweep (2026-04-26) surfaced **three real correctness bugs** that the test suite was not exercising — tracked as Phase 0.4. Tasks 51 + 52 (Trace / TraceCall list-vs-singular spec corrections) landed 2026-04-26 — `invalid_contract` count 11 → 9, full suite green. A subsequent Codex consultation (2026-04-26) added a fourth pre-release blocker — `Cartouche.Solana.Transaction.deserialize/1` raises `FunctionClauseError` / `MatchError` on malformed bytes instead of honoring its `{:ok, _} | {:error, _}` contract — tracked as Task 56 (✅ landed 2026-04-27, bundled with Task 57's zero-signer boundary fix). Task 53 (V1 r/s/v unification + latent `decode → recover_signer` crash) landed 2026-04-28 — `invalid_contract` count 9 → 8, full suite green, V1 coverage 93.33% → 100%. **Task 6 (`mix hex.publish`) is the only remaining pre-release item** and requires the user to run the publish command (hex API key / OTP).

- **Task 6** — `mix hex.publish`. Staged diff is ready: `mix deps.get && mix test && mix dialyzer.json` → `git tag v0.1.0` → `mix hex.publish`. Requires user to run the publish command (hex API key / OTP).

After `0.1.0`: Phase 1 (spec corrections — immediate onchain `@dialyzer` wins; Phase 1.4 scope narrows to just `from_hex/1` per the 2026-04-24 re-run), then parallel work through Phases 2–9 as priority dictates.

---

## Phase 0: Ship `0.1.0`

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Reset `mix.exs` version `1.6.1` → `0.1.0-dev` [D:1/B:3/U:7 → Eff:5.0] 🎯 | ✅ | Done 2026-04-24 |
| 2 | Full `mix test.json --quiet` pass on the ported code [D:3/B:5/U:7 → Eff:2.0] 🚀 | ✅ | 665 passed / 0 failed on 2026-04-24. Also cleared two stale test warnings (`test/support/vm_test_helpers.ex:11` missed by C1 pin sweep, `test/solana/pda_test.exs:137` underscored-then-used var) |
| 3 | `mix dialyzer.json --quiet` — inventory remaining `invalid_contract` warnings, confirm they match the pre-rename audit (Phases 1, 3, 4, 6 below) [D:2/B:3/U:6 → Eff:2.25] 🚀 | ✅ | 2026-04-24: 11/11 `invalid_contract` accounted for; total 1,626 matches the post-abi-fix benchmark. Phase 1.4 scope narrows to `from_hex/1` only (see Phase 1.4 note below) |
| 4 | `mix docs` clean build with cartouche branding intact [D:2/B:3/U:5 → Eff:2.0] 🚀 | ✅ | Done 2026-04-24; `doc/index.html`, `doc/llms.txt`, `doc/Cartouche.epub` all build; `llms.txt` header reads `Cartouche v0.1.0-dev`; 54 `Cartouche.*` entries in `api-reference.html`; only `signet`/`hayesgm` hits in `doc/` are the README attribution links. Pre-existing ex_doc type-ref warnings split out as Task 36 |
| 5 | Update `README.md` installation section — replace the "not recommended yet" placeholder with real install instructions [D:1/B:3/U:7 → Eff:5.0] 🎯 | ✅ | Done 2026-04-25 as part of Task 37 prep. Status block + install snippet activated |
| 6 | Tag `0.1.0`, publish to hex [D:1/B:5/U:8 → Eff:6.5] 🎯 | ⬜ | Staged and ready 2026-04-25. Pre-publish sequence: `mix deps.get && mix test && mix dialyzer.json` → `git tag v0.1.0` → `mix hex.publish`. Acceptance: `mix hex.info cartouche` shows `0.1.0` |
| 36 | Silence ex_doc `documentation references type "X" but the module is hidden` warnings surfaced by `mix docs` [D:2/B:2/U:4 → Eff:1.5] 📋 | ✅ | Done 2026-04-25. Replaced `@moduledoc false` with descriptive `@moduledoc` on the six referenced submodules (`Cartouche.VM.Input`, `Cartouche.VM.Context`, `Cartouche.VM.ExecutionResult`, `Cartouche.Trace.Action`, `Cartouche.Receipt.Log`, `Cartouche.DebugTrace.StructLog`). `mix docs` now emits zero warnings; 665/665 tests still green |
| 37 | Publish cut — version bump, CHANGELOG release section, mix.exs `:package` polish, README install activation [D:1/B:3/U:5 → Eff:4.0] 🎯 | ✅ | Done 2026-04-25. `mix.exs` version → `0.1.0`; CHANGELOG `[Unreleased]` moved under `[0.1.0] — 2026-04-25`; `:package` updated (`maintainers: ["ZenHive"]`, dropped `test/support` from `:files`, added `CHANGELOG*`, added `CHANGELOG.md` to `docs[:extras]`, added `Changelog` link); README Status + Installation activated |
| 40 | Generator (`lib/mix/cartouche.gen.ex`) credo cleanup [D:5/B:2/U:3 → Eff:0.5] ⚠️ | ✅ | Done 2026-04-26 — bundled with the IConsole bytecode-predicate fix per the touched-files credo rule. (1) L153 `rename_dups/1` nesting → `accumulate_named_abi/2` + `dedup_named_abi/5` + `maybe_rename_dup_fn/5`. (2) L170 `get_encode_calls/2` cyclomatic → `merge_encode_call_result/2`. (3) L247 `encode_function_call/3` cyclomatic → ~16 `build_*_fn/1` helpers + `select_emitted_fns/3` + argument-spec helpers (`function_names/1`, `derive_argument_types/1`, `build_argument_specs/1`, `signature_data/1`, `abort?/3`, `build_function_quotes/1`). (4) L337 nesting → resolved by #3. Also landed `strip_zero_arity_def_parens/1` post-process to drop the ~382 `ParenthesesOnZeroArityDefs` flags from generated output (macro source must keep `def unquote(name)()` for AST validity; text-level strip rewrites to `def name`). 6 `String.to_atom/1` callsites carry `# sobelow_skip` annotations (build-time codegen). 656/656 tests green; 0 credo issues on touched files |
| 38 | Delete `Cartouche.Util` grab-bag — redistribute helpers into focused modules, drop `@deprecated` aliases [D:3/B:3/U:5 → Eff:1.33] 📋 | ✅ | Done 2026-04-25. Created `Cartouche.Address`, `Cartouche.Chain`, `Cartouche.Wei`, `Cartouche.HTTP`, and promoted `Cartouche.RecoveryBit`. Absorbed `decode_hex_input!/1`, `encode_bytes/2`, `pad/2`, `nibbles/1`, `checksum_address/1` into `Cartouche.Hex`. Deleted 7 `@deprecated` decode/encode aliases + `keccak/1` defdelegate. `nil_map/2` inlined as module-local private in `Cartouche.Trace` / `Cartouche.Trace.Action`. Also landed the Phase 1.1 `:no_return` atom → `no_return()` fix on `RecoveryBit` during the promotion. 651 tests green; `grep Cartouche.Util` returns zero hits outside history |

**Acceptance:** onchain can `mix deps.update cartouche` against `{:cartouche, "~> 0.1"}` and resolve.

---

## Phase 0.4: Pre-`0.1.0` correctness fixes

Four real bugs caught by the type system / static analysis but not exercised by the test suite. Three surfaced during the doctor-driven typespec sweep (2026-04-26) — Tasks 51 + 52 (consumer-facing MatchError potential — Trace / TraceCall list-vs-singular type mismatch; both ✅ landed 2026-04-26) and Task 53 (latent crash on a public API path — `V1.decode → recover_signer → ArgumentError` on signed RLP; ✅ landed 2026-04-28). A fourth was added by a follow-up Codex consultation (2026-04-26) — Task 56 (`Cartouche.Solana.Transaction.deserialize/1` raises on malformed bytes instead of returning `{:error, _}`; ✅ landed 2026-04-27 bundled with Task 57's zero-signer boundary fix). All Phase 0.4 blockers are cleared; Task 6 (`mix hex.publish`) is the only remaining pre-release item.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 51 | `Cartouche.Trace.t().trace_address` typed singular but runtime is a list [D:1/B:5/U:7 → Eff:6.0] 🎯 | ✅ | Done 2026-04-26. Spec narrowed to `[<<_::160>> \| integer()]` at `lib/cartouche/trace.ex:184`. Added focused ExUnit `describe "deserialize/1 — trace_address list shapes"` block in `test/trace_test.exs` covering the mixed-element union (`[42, <<_::160>>]`), the empty-list boundary, and `deserialize_many/1` round-trip — explicitly rather than via doctest, since doctests read as documentation and don't pin edge cases. Bundled with Task 52. Dialyzer drops `trace.ex:412 invalid_contract`; suite green |
| 52 | `Cartouche.TraceCall.t().trace` typed singular but runtime is a list [D:1/B:5/U:7 → Eff:6.0] 🎯 | ✅ | Done 2026-04-26. Spec narrowed to `[Cartouche.Trace.t()]` at `lib/cartouche/trace_call.ex:20`. Added focused ExUnit `describe "deserialize/1 — trace list shape"` block in `test/trace_call_test.exs` covering the empty-trace-list boundary and `deserialize_many/1` round-trip. Bundled with Task 51. Dialyzer drops `trace_call.ex:124 invalid_contract` |
| 53 | V1.t() Schrödinger r/s/v + latent `decode → recover_signer` crash [D:4/B:7/U:6 → Eff:1.63] 🚀 | ✅ | Done 2026-04-28. Option B implemented (integers throughout, single source of truth). `add_signature/2` (`lib/cartouche/transaction.ex:170`) now decodes incoming binary `r`/`s` via `:binary.decode_unsigned/1` so they match the spec and `V1.new/7` / `V1.decode/1` storage. `get_signature/1` second clause (`transaction.ex:196`) rebuilds the signature with integer big-endian 256-bit segments (`<<r::big-256, s::big-256, v_enc::binary>>`) — byte-equivalent to the prior 32-byte binary form, so `add_signature → get_signature` round-trips bit-for-bit. As a side benefit, `add_signature(...) |> encode()` now produces canonical RLP for r/s (leading zeros stripped) — the prior binary form was technically non-canonical on the wire. Doctest at `transaction.ex:155–167` updated to show `r: 1, s: 2` post-`add_signature` (the only doctest whose expected output changed). Tests added in `test/transaction_test.exs` (new `describe "V1 (Task 53)"` block): malformed-RLP fallback for `decode/1` (closes coverage gate), full `build_signed_trx → encode → decode → recover_signer` round-trip (proves the latent `ArgumentError` is fixed — failed pre-fix exactly as documented), the empty-sig RLP boundary (`r:0, s:0` → `recover_signer` reports missing signature), and an adversarial 33-byte r/s RLP fixture (added during the staged-review pass) — `decode/1` now guards `byte_size(r) <= 32 and byte_size(s) <= 32` so the new `<<r::big-256>>` reconstruction in `get_signature/1` can't raise `ArgumentError` on r ≥ 2^256 reachable through `decode → recover_signer`. V1 coverage 93.33% → 100%; dialyzer drops `transaction.ex:169 invalid_contract` (count 9 → 8); 748/748 tests green |
| 56 | Harden `Cartouche.Solana.Transaction.deserialize/1` crash paths [D:2/B:6/U:6 → Eff:3.0] 🎯 | ✅ | Done 2026-04-27. Added private `safe_decode_compact_u16/1` returning `{:ok, val, rest} \| {:error, :truncated_compact_u16}` (public `decode_compact_u16/1` tuple contract preserved); swapped internal callsites in `deserialize/1` and `deserialize_message/1`. Rewrote `read_instructions/3` with `with` + a `read_size_prefixed/2` helper modelled on `read_signatures/3` / `read_pubkeys/3`; added a `(_, _, _) -> {:error, :insufficient_instruction_data}` fallback. Added a `deserialize_message(_), do: {:error, :invalid_message_header}` fallback for sub-3-byte headers (caught by the new test for truncated headers — `deserialize_message/1` was raising `FunctionClauseError` independent of compact-u16 fixes). New ExUnit `describe "deserialize/1 — malformed input (Task 56)"` block in `test/solana/transaction_test.exs` covers `<<>>`, truncated compact-u16, oversized signature count, truncated header / pubkey / blockhash / instruction header / accounts / data — 9 cases, all `assert {:error, _}`. Coverage 95.56% → 98.97% on `Cartouche.Solana.Transaction`; full suite green; dialyzer clean on touched file |

---

## Phase 0.5: Post-`0.1.0` hardening

Bugs and follow-ups that don't block `0.1.0` and warrant their own commits — initially generator-related (surfaced during the Task 40 staged review 2026-04-26), extended through subsequent Phase 0.4 work (Trace `traceAddress` audit), Sleuth atom-table risk (Task 48), and Solana hardening from the Codex consultation (2026-04-26).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 41 | Generator bytecode-flag separation — init vs deployed [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | **Blocked on Task 44.** `Mix.Tasks.Cartouche.Gen.build_module/3` derives a single `has_bytecode` flag from `not Enum.empty?(bytecode_decl)` (init bytecode) and threads it through `get_encode_calls/2`, `encode_function_call/3`, `abort?/3`, and `select_emitted_fns/3`. But the `:pure` branch's `exec_vm_fn` uses `deployed_bytecode/0` while the constructor branch uses `bytecode/0` — different flags belong on different gates. Asymmetric artifacts (init bytecode present but deployed absent, or vice versa) currently misbehave: the first emits `exec_vm_*` referencing undefined `deployed_bytecode/0` → `CompileError` at consumer load; the second skips `exec_vm_*` even though the runtime would have worked. Pre-existing in upstream; preserved by Task 40's refactor. Trigger probability is low (Hardhat/Foundry always pair both bytecodes), so deferred from the Task 40 commit. Fix shape: add `has_deployed_bytecode` alongside `has_bytecode`, gate `:pure`'s `exec_vm_*` on the deployed flag, gate constructor `abort?` on the init flag. Add regression tests for both asymmetric shapes. Discovered during the Task 40 staged review |
| 42 | Generator `decode_error/1` template — drop dead `if true ... else ... end` branch [D:1/B:1/U:2 → Eff:1.5] 📋 | ⬜ | **Blocked on Task 44.** `Mix.Tasks.Cartouche.Gen.get_encode_calls/2` emits a fallback `def decode_error(_) do; if true do :not_found else {:ok, "Impossible", <<>>} end; end` for every generated module. Dialyzer correctly flags the `else` arm as unreachable (`pattern can never match the type true`) — surfaces as `lib/cartouche/contract/i_console.ex:18704: The pattern can never match the type true` and on every other generated contract. Same fix shape on the `decode_call/1` and `decode_event/2` fallbacks if they share the dead-branch pattern. Replace with `def decode_error(_), do: :not_found`. Regenerate IConsole (and any other generated modules under `lib/cartouche/contract/`) once the template is fixed. Pre-existing in upstream; surfaced during Task 40's pre-commit hook run |
| 44 | Generator coverage push — raise `Mix.Tasks.Cartouche.Gen` to ≥80% before Tasks 41 + 42 [D:3/B:4/U:6 → Eff:1.67] 🚀 | ⬜ | Currently 73.05% (69 uncovered lines per `mix test.json --cover` 2026-04-26). Gate for Tasks 41 (bytecode-flag separation) and 42 (`decode_error` dead branch). Cover `build_module/3` happy + asymmetric-bytecode shapes, `get_encode_calls/2` fallback emitter, `encode_function_call/3` per-arity branches, `abort?/3` true/false paths, `select_emitted_fns/3` selection logic, and the `decode_error/1` / `decode_call/1` / `decode_event/2` template fallbacks. Use a tiny synthetic ABI fixture rather than regenerating IConsole. Acceptance: `Mix.Tasks.Cartouche.Gen` ≥ 80% on `mix test.json --cover` |
| 47 | Exclude generated `Cartouche.Contract.IConsole` from coverage measurement [D:1/B:1/U:3 → Eff:2.0] 🚀 | ⬜ | Headline coverage 22.22% is dominated by IConsole's 5,715 uncovered lines (`mix test.json --cover` 2026-04-26). Exclude it via `def project` `:test_coverage` config (`ignore_modules: [Cartouche.Contract.IConsole]` or a regex covering `Cartouche.Contract.*` if all generated bindings should be ignored). Generated bytecode-binding modules don't have meaningful coverage — what matters is the generator's coverage (Task 44) and the consumer's tests. Acceptance: post-exclusion `coverage.total_percentage` reflects hand-written code only; CI thresholds (if added) become meaningful |
| 49 | ~~Resolve `Cartouche.Transaction.V2.encode/1` spec duplication~~ — **superseded by Task 54** | 🔶 | **Folded into Task 54.** The narrow `V2.encode/1` spec union targeted here is obsoleted by the structural `Cartouche.Transaction.Call` extraction — widening `V2.t()` signature fields to nullable is the surface symptom; Call extraction fixes the abstraction boundary that drives the symptom. Doing both is wasted work. Closing as duplicate of Task 54 |
| 54 | Extract `Cartouche.Transaction.Call` — collapse the V2-as-eth-call-shape lie [D:6/B:5/U:5 → Eff:0.83] ⚠️ | ⬜ | **Replaces Task 49.** Generator-emitted `Cartouche.Contract.Sleuth.build_trx_query/3` (`lib/cartouche/contract/sleuth.ex:33`) returns `%V2{destination: contract, data: encode_query(q, c)}` — partial-struct (2 of 12 fields populated). `V2.t()` (`lib/cartouche/transaction.ex:232–245`) declares all 12 fields non-nullable. Dialyzer correctly identifies a contract violation; the cascade surfaces as `no_return` + `invalid_contract` warnings in `Cartouche.Sleuth` (`lib/cartouche/sleuth.ex` — the hand-written wrapper) propagating through `Sleuth.call_query → Sleuth.query_internal/5` to the public Sleuth entrypoints. Runtime is fine because `Cartouche.RPC.to_call_params/2` (`rpc.ex:1533–1553`) tolerates the nils via `nil_map/2` (`rpc.ex:1607`); `call_trx/2` (`rpc.ex:298`) routes through it. **The fix is structural, not a spec widening.** Eth_call params are not transactions — never signed, never broadcast, only executed. The current `%V2{}` masquerade is the abstraction lie. Define `defmodule Cartouche.Transaction.Call do` with at minimum `destination: <<_::160>>, data: binary()` (audit `RPC.to_call_params/2` to determine if `value` / `gas` / `from` should also be Call-shape fields). Update the generator template (`lib/mix/cartouche.gen.ex` `build_trx_*` quote blocks) to emit `%Call{}` instead of `%V2{}`. Extend RPC dispatch to accept `V1.t() \| V2.t() \| Call.t()`. Regenerate `Cartouche.Contract.IConsole` and `Cartouche.Contract.Sleuth`. **Fix scope spans two modules:** the generator template (origin of the `%V2{}` masquerade emitted into `lib/cartouche/contract/sleuth.ex`) and `Cartouche.Sleuth` (where the cascade surfaces). **Out of scope (separate task if pursued):** Unsigned/Signed split for V1/V2 — Codex flagged the third rail (RLP/signing/recovery), and that refactor would inflate this task significantly without addressing the Sleuth cascade. **Coverage gate:** `Cartouche.RPC`, `Cartouche.Transaction`, generator (Task 44 already gates this), and consumer test suite. Critical-tier modules touched. Audit before mutating. Acceptance: the Sleuth dialyzer cascade collapses; `mix test.json --quiet` green; round-trip tests for both V2 transactions (signed) and Call shapes (eth_call); narrow `.dialyzer_ignore.exs` entries (the two generated files) unchanged because the underlying type contract is now honest. Discovered + scoped during Codex consultation 2026-04-26 |
| 50 | Generator emits `@doc`/`@spec` on generated bindings — drop `.doctor.exs` `ignore_paths` [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Natural co-deliverable with Task 42 (template fix → IConsole regeneration). `Mix.Tasks.Cartouche.Gen` currently emits no `@doc` or `@spec` on the functions it builds (`encode_*`, `decode_*`, `*_selector`, `call_*`, `estimate_gas_*`, `call_log_*`, `exec_vm_*`, etc.). The doctor-driven typespec sweep (2026-04-26) hit this and had to add `.doctor.exs` `ignore_paths: [~r"^lib/cartouche/contract/"]` to suppress the resulting flood of missing-doc/spec warnings (Doctor doesn't currently see them with the path-exclude in place). Fix shape: extend each `def unquote(name)(args)` block in the generator's `quote do ... end` templates to attach a `@doc` (one-liner derived from ABI metadata — function name, signature, brief purpose) and a `@spec` (derived via existing ABI type → Elixir type mapping). Once Tasks 41/42/44 land and IConsole is regenerated, this becomes a small marginal additional template change. Acceptance: regenerated `lib/cartouche/contract/i_console.ex` (and other bindings) carry `@doc` + `@spec` on every public function; `.doctor.exs` `ignore_paths: [~r"^lib/cartouche/contract/"]` removed; `mix doctor` clean. Discovered during the staged review of the typespec sweep |
| 48 | Harden `Cartouche.Sleuth` atom-table risks [D:5/B:4/U:5 → Eff:0.9] ⚠️ | ⬜ | Three `String.to_atom` callsites in `lib/cartouche/sleuth.ex` warrant the same hardening — the `query_by/3` atom-deriving pair (lines 26/27, currently in `.sobelow-skips`) plus `name_keyword/1` (line 196, not currently sobelow-flagged but identical risk shape since it `String.to_atom`s ABI field names). All three are bounded by compile-time atoms (the `encode_*`/`*_selector` functions are generated by `mix cartouche.gen`; field-name atoms get pre-created when generated function arg names are defined) — but the `String.to_atom` calls mint lazily at runtime, so the risk is real. Fix shape: swap to `String.to_existing_atom`, raise on missing atom (likely correct behavior). **Pre-implementation gate:** `Cartouche.Sleuth` is critical business logic (the ABI-decoded eth_call wrapper); raise its module coverage to ≥95% before swapping (the swap is a contract-narrowing — not the trivial-rename exemption — so the gate applies). Discovered during the DebugTrace audit (2026-04-26 hardening, see CHANGELOG `[Unreleased]`) |
| 55 | Harden `Cartouche.Trace.deserialize/1` against missing/nil `traceAddress` [D:1/B:2/U:3 → Eff:2.5] 🎯 | ⬜ | `lib/cartouche/trace.ex:423` (the `Enum.map(params["traceAddress"], &decode_address_or_number/1)` line, marked with `TODO(Task 55)`) raises `Protocol.UndefinedError` if `params["traceAddress"]` is missing or `nil` — `deserialize/1` only pattern-matches on `"subtraces"` and `"type"`. Pre-existing latent crash on malformed RPC input. Per `critical-rules.md` "NEVER HIDE TEST FAILURES" the Task 51 test suite intentionally does **not** pin the broken behavior with `assert_raise`. **Audit resolved 2026-04-26 (Task 51 staged review, Codex dialogue):** OpenEthereum / Infura `trace_transaction` schemas describe `traceAddress` as the call-tree location identifier, root shown as `[]` (empty list, always present); neither reference marks the field optional. Omission is a contract violation, not a valid shape — soft `\|\| []` would silently coerce corruption. **Fix shape (decided):** replace `Enum.map(params["traceAddress"], …)` with a guard that raises `ArgumentError, "missing traceAddress in trace_transaction result element"` when the key is absent or `nil`; map otherwise. Add a test asserting the raise on `%{...}` without `"traceAddress"` and on `%{"traceAddress" => nil}`. Discovered during Task 51 implementation 2026-04-26 |
| 43 | Pre-credo coverage push for cleanup-target modules [D:3/B:5/U:7 → Eff:2.0] 🚀 | ✅ | Done 2026-04-26. Raised test coverage on the six modules slated for credo-strict cleanup so the refactor session can rename / restructure / silence flags safely. New blocks landed in `test/assembly_test.exs` (data-driven `show_opcode/1` table covering every named-atom arm + PUSH/DUP/SWAP/INVALID tuple coverage, multi-arity `compile/1` 3–7, `transform_jumps` missing-jump-dest path, full PUSH1–32 / DUP1–16 / SWAP1–16 / 0xfe `disassemble_opcode/1`, per-clause `opcode_size/1`, `constructor/1` wrap, exception-struct defaults), `test/receipt_test.exs` (contract-creation receipt with `to: nil`/`contractAddress` populated; log shapes for empty data / 2-topic / 4-topic), `test/open_chain_test.exs` (TestClient extended with magic-byte signature dispatch for `ok=false` / non-JSON / transport-error / multi-result / empty paths; `lookup_error` / `lookup_error_and_values` short-binary clauses; `Signatures.deserialize/1` filter behavior), `test/transaction_test.exs` (`V2.new/9` chain-id-nil fallback, `V2.new/12` nil fee fields, `build_trx_v2` ABI-tuple + raw-binary call-data, `build_signed_trx_v2` happy-path with signer-recovery roundtrip + callback short-circuit, `V2.decode` malformed-RLP body), `test/sleuth_test.exs` (try-apply rescue with descriptive `RuntimeError` when the contract module is missing `bytecode/0`), and `test/solana/signer_test.exs` (explicit cache-hit test with `:sys.get_state/1` confirming the `:address` key is populated after the first call). Bundled with the coverage work: bug fix in `lib/cartouche/open_chain.ex:200` — `Enum.join(found_signatures, ",")` over a list of `{sig, name}` tuples replaced with `Enum.map_join(found_signatures, ",", fn {_, name} -> name end)`. Was crashing `Protocol.UndefinedError` instead of returning `{:error, "Multiple matching signatures: ..."}` on the `raise_on_multiple: true` path. Surfaced while writing the test for the multi-result error path; per `critical-rules.md` "NEVER HIDE TEST FAILURES" the test now asserts the corrected return shape (including the actual signature names) rather than pinning the broken raise |
| 57 | Fix `Cartouche.Solana.Transaction.sign_partial/2` zero-signer boundary [D:1/B:3/U:3 → Eff:3.0] 🎯 | ✅ | Done 2026-04-27 (bundled with Task 56). Appended `//1` step to the range at `lib/cartouche/solana/transaction.ex:415` — `0..(num_signers - 1)//1` yields `[]` when `num_signers == 0` and is behaviour-preserving for `num_signers >= 1`. New ExUnit `describe "sign_partial/2 — zero-signer boundary (Task 57)"` block asserts `signatures == []` for a synthetic 0-signer message (real Solana txs always have ≥1 fee payer; the test exists purely to pin the boundary against future regression) |
| 58 | Add `Cartouche.Filter` expired-filter test (resolve `test/filter_test.exs:53` TODO) [D:1/B:1/U:2 → Eff:1.5] 📋 | ⬜ | `test/filter_test.exs:53` carries `# TODO(Task 58): Test expired filter` — small standing test gap. Write the test, drop the TODO. Reuse the existing test setup; verify what shape `Cartouche.Filter` actually returns for expired filters before writing the assertion (per `critical-rules.md` "NEVER HIDE TEST FAILURES" — don't pin broken behavior). Discovered during Codex consultation 2026-04-26 |
| 59 | Reach 1.8 hygiene pass — redundant computations + suspicious dead binds [D:1/B:2/U:1 → Eff:1.5] 📋 | ⬜ | `mix reach.smell` + `mix reach.dead_code` (reach 1.8.0, run 2026-04-28) surfaced a small cluster of behavior-preserving cleanups. Redundant computations — dedupe by extracting a local: `lib/cartouche/solana/transaction.ex:201–202` (`length/1` called twice on the same arg), `lib/cartouche/hex.ex:353–354` (`byte_size/1` twice), `lib/cartouche/transaction.ex:512–513` (same binary literal built twice), `lib/cartouche/rpc.ex:193,195` (`inspect/1` twice across an interpolated log line). Dead binds in `lib/mix/cartouche.gen.ex:816` (`module_name = String.to_atom(...)` value never read) and `:817` (result of `List.flatten/1` discarded) — investigate before deleting; an unused result in the generator may indicate an unfinished branch, not pure dead code. Two `Macro.underscore/1` repeats in the same generator (`:353–354`, `:396–397`) bundled here. **Coverage-gate caveat:** `Cartouche.Hex` and `Cartouche.Transaction` are critical-tier (≥95%); `Mix.Tasks.Cartouche.Gen` items are gated on Task 44 (≥80% generator coverage push) — these refactors hover near the "pure rename" exemption but extracting to a local technically mutates the AST, so verify each touched module is at tier via `mix test.json --cover` before changing, or split the gen.ex items off and let Task 44 land first. Acceptance: re-run `mix reach.smell` and `mix reach.dead_code` — listed locations drop out; `mix test.json --quiet` green; no new dialyzer warnings on the touched modules. Discovered while updating the global `reach.md` include for reach 1.8 (2026-04-28) |

---

## Phase 1: Spec corrections (immediate onchain wins)

**Why:** These are the load-bearing fixes for onchain's `@dialyzer` suppressions. Every one is grounded in `mix dialyzer.json` output from the pre-rename audit (2026-04-21). All are surgical — spec-only edits, no runtime change.

### 1.1 `Cartouche.RecoveryBit` — `:no_return` atom → `no_return()` type ✅

**Landed 2026-04-25 as part of Task 38** (Util grab-bag deletion). Promotion of `Cartouche.Util.RecoveryBit` to a top-level `Cartouche.RecoveryBit` module corrected both specs in flight:

| Function | Fix |
|----------|-----|
| `RecoveryBit.normalize/2` | `\| :no_return` → `\| no_return()` |
| `RecoveryBit.normalize_signature/2` | `\| :no_return` → `\| no_return()` |

**Follow-up:** `Cartouche.RecoveryBit` doctests for `normalize/2` (`:eip155` branch, returns `46`) and `recover_base/1` (`v=47` raise message bakes `chain_id=5`) are only correct under `chain_id=:goerli` (the cartouche test-config value). Pre-existing in upstream `Cartouche.Util.RecoveryBit`. Not a correctness bug — tests pass — but a portability/documentation hazard. Tracked as Task 39.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 39 | RecoveryBit doctest chain-id portability cleanup [D:2/B:1/U:1 → Eff:0.5] ⚠️ | ⬜ | Either parameterize the expected output to read `Cartouche.Application.chain_id()` at doctest time, or rewrite the `:eip155`-branch `normalize/2` doctest and the `recover_base(47)` raise doctest to use chain-agnostic examples. Discovered during Task 38 staged review |

### 1.2 `Cartouche.Util.to_wei/1` — narrow `number()` → `non_neg_integer()`

`@spec to_wei/1 :: number()` (line 257) but every clause returns `integer()` and amounts are non-negative by domain (wei is a discrete count).

### 1.3 `Cartouche.Signer.sign_direct/4` — `mfa()` → `{module(), atom(), list()}`

Dialyzer reports `signer.ex:141 invalid_contract`. 3rd arg specced as `mfa()` (which Elixir defines as `{module(), atom(), arity :: non_neg_integer()}`) but the impl receives `{module(), atom(), args :: list()}`. The third element type does not overlap.

### 1.1–1.3 bundled task

Phase 1.1 landed 2026-04-25 (Task 38). Phase 1.3 landed 2026-04-26 (typespec sweep — see CHANGELOG `[Unreleased]`). Remaining: `to_wei/1` narrowing (now in `Cartouche.Wei`).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 7+8+9 | Phase 1.1–1.3 surgical spec fixes [D:1/B:3/U:6 → Eff:4.5] 🎯 | 🔶 | Phase 1.1 ✅ done under Task 38 (`Cartouche.RecoveryBit` promotion). Phase 1.3 ✅ done 2026-04-26 — `mfa()` BIF replaced with `{module(), atom(), [any()]}` on both `Cartouche.Signer.sign_direct/4` (the original Phase 1.3 target) AND `Cartouche.Signer.start_link/1` (caught during the doctor-driven typespec sweep — the regression was about to ship via a brand-new `start_link` spec using the same wrong `mfa()` type). Remaining: narrow `Cartouche.Wei.to_wei/1` return to `non_neg_integer()` (Phase 1.2). Verification: `mix dialyzer.json` loses the `signer.ex:141 invalid_contract` |

### 1.4 `Cartouche.Hex` return-type specs

**Root cause:** private `Cartouche.Hex.decode_hex_/1` (`lib/cartouche/hex.ex:374`) returns `{:ok, t()} | :invalid_hex` but is specced `{:ok, t()} | :error`. All public callers inherit this:

| Function | Line | Current `@spec` | Actual return |
|----------|------|-----------------|---------------|
| `decode_hex/1` | 80 | `{:ok, t()} \| :error` | `{:ok, t()} \| :invalid_hex` |
| `decode_hex_number/1` | 245 | `{:ok, integer()} \| :error` | `{:ok, integer()} \| :invalid_hex` |
| `from_hex/1` | 91 | `t() -> String.t()` | `t() -> {:ok, t()} \| :invalid_hex` (alias for `decode_hex`) |
| `from_hex!/1` | 102 | `t() -> String.t()` | `t() -> t()` (alias for `decode_hex!`) |

Doctests and `@doc` examples already show the correct shape; only the `@spec` lines disagree. Fix is surgical — update the four specs, no implementation change.

**Scope update (2026-04-24 dialyzer re-run):** only `from_hex/1` (now at `hex.ex:93`) still fires `invalid_contract`. The `decode_hex/1`, `decode_hex_number/1`, and private `decode_hex_/1` warnings are no longer flagged — but the specs themselves still mismatch the runtime: `hex.ex:82` (`decode_hex/1`), `hex.ex:247` (`decode_hex_number/1`), and `hex.ex:375` (private `decode_hex_/1`) all declare `:error` while the body returns `:invalid_hex` (verified 2026-04-24). Dialyzer's silence is a PLT / cascade artifact, not an incidental fix — all four Phase 1.4 specs remain load-bearing for onchain's `@dialyzer` strip.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 10+11+12+13 | Phase 1.4 Hex spec audit + `from_hex/1` fix + doctest coverage [D:2/B:7/U:9 → Eff:4.0] 🎯 | ⬜ | Fix `decode_hex/1` + private `decode_hex_/1` (Task 10, `hex.ex:82` + `hex.ex:375`: `:error` → `:invalid_hex`) and `decode_hex_number/1` (Task 11, `hex.ex:247`) — specs still wrong per the table above, dialyzer is just not flagging them right now. Fix `from_hex/1` + `from_hex!/1` (`hex.ex:93 invalid_contract` — the only live warning, Task 12). Add doctest coverage for all four specs proving the real return shape (Task 13) — required for upstream acceptance if pitched (see Phase 10); also grounds the local fix |

**Downstream impact once shipped in `0.1.x`:** onchain strips its `@dialyzer {:no_match, …}` blocks from `Onchain.Hex` and (via cascade through `Contract.call/5 → ABI.decode_response/2`) from the ABI / ERC / ENS / Multicall modules. Full downstream strip additionally needs the external `abi` fix tracked in Phase 10.

---

## Phase 2: `Cartouche.RPC.send_rpc/3` error-shape spec

**Why:** onchain carries `@dialyzer {:no_match, do_rpc: 3}` because the current spec promises `%{code: int, message: str}` for all errors, but `send_rpc/3` actually returns several other error shapes at runtime.

Confirmed runtime error shapes (`lib/cartouche/rpc.ex:84–203`, `lib/cartouche/http.ex` normalize_finch_result/1):

| Source | Returned shape |
|--------|----------------|
| Finch non-2xx | `{:error, %Finch.Response{}}` |
| Finch transport | `{:error, "[Cartouche] HTTP client error: …"}` (string) |
| Finch unknown | `{:error, "[Cartouche] Unknown error: …"}` (string) |
| Invalid JSON-RPC envelope | `{:error, %{code: -999, message: "…"}}` |
| Revert with decoded error (code 3) | `{:error, %{code:, message:, revert:, error_abi:, error_params:}}` (extra fields vs spec) |
| `decode: :hex` path with bad hex | bare `:invalid_hex` atom (not wrapped in `{:error, …}`) |
| Custom `decode:` fn raises | `{:error, "failed to decode `<method>` response: <inspect>"}` |
| **Non-JSON-encodable `method` or `params`** | **raises `Protocol.UndefinedError` / `Jason.EncodeError` — bypasses `{:ok,_}\|{:error,_}` contract entirely** (`rpc.ex:162`, `Jason.encode!(body)`). Same pattern in `lib/cartouche/solana/rpc.ex:68` (`Cartouche.Solana.RPC.send_rpc/3`). |

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 14+15+35 | Phase 2 RPC error-shape widening [D:4/B:7/U:7 → Eff:1.75] 🚀 | ⬜ | **Step 1 (Task 14):** re-audit `send_rpc/3` `@spec` vs runtime shapes on the ported code — confirm the table above; some shapes may have been tightened in intervening signet commits before the fork. **Step 2 (Task 15):** widen or tag-split the error type with doctest coverage per shape. Keep `%{code, message}` as the JSON-RPC-error branch; union in the others. **Step 3 (Task 35):** rescue `Jason.EncodeError` / `Protocol.UndefinedError` at `Jason.encode!(body)` in **both** `lib/cartouche/rpc.ex:162` (Ethereum) and `lib/cartouche/solana/rpc.ex:68` (Solana) → `{:error, {:invalid_params, _}}`, so non-JSON-encodable inputs honor the `{:ok,_}\|{:error,_}` contract on both transports instead of raising. Triggers (apply to both): `<<255>>` method binary (non-UTF-8 passes `is_binary/1` but Jason raises); params containing tuples / atom-keyed maps. Doctests per trigger in each RPC module. The new `{:invalid_params, _}` joins the union from Step 2. Discovered 2026-04-24 during onchain Task 59 (`Onchain.RPC.call/3` — generic JSON-RPC passthrough; Ethereum side); Solana side surfaced 2026-04-26 during Codex consultation. Once this lands, all `Onchain.RPC.*` wrappers automatically honor their `@spec` and the same guarantee extends to Solana RPC consumers |

**Blast radius** (from `mix reach.impact Cartouche.RPC.send_rpc/3`, pre-rename): 6 direct callers break on signature change (`get_balance/2`, `get_transaction_count/2`, `eth_block_number/1`, `eth_chain_id/1`, `set_filter/1`, `Cartouche.Filter.handle_info/2`), 1 transitive (`Cartouche.Signer.init/1`), no return-value dependents. Behavior-preserving spec-widening is low-risk; a union-type split needs all 6 direct callers to still type-check.

---

## Phase 3: `Cartouche.Trace` + `Cartouche.TraceCall` deserialize specs

**Why:** Dialyzer reports `trace.ex:408` and `trace_call.ex:124` as `invalid_contract`. The struct returned by `deserialize/1` has fields with union types (`nil | binary()`, `nil | <<_:160>>`, etc.) that the module's `@type t` declaration doesn't allow.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 16+17+18 | Phase 3 Trace + TraceCall deserialize specs + tests [D:3/B:2/U:4 → Eff:1.0] 📋 | ⬜ | Update `Cartouche.Trace.@type t` (and nested `Cartouche.Trace.Action` type) to match dialyzer's inferred shape — extend fields to `nil \| …` where runtime proves it (Task 16). Update `Cartouche.TraceCall.@type t` analogously (Task 17) — piggybacks on Task 16 if `TraceCall` embeds `Trace.t()`. Ground the widened types with unit tests exercising `deserialize/1` on representative JSON (with and without optional fields) (Task 18) |

---

## Phase 4: `Cartouche.Typed` internal-function specs

**Why:** Dialyzer reports `typed.ex:571` (`encode_value_map/3`) and `typed.ex:585` (`find_type/2`) as `invalid_contract`. Both specs completely disagree with the success typing — looks like copy-paste from a sibling function or a stale spec after a refactor.

- `encode_value_map/3`: spec returns a map; impl returns a `bitstring()`.
- `find_type/2`: spec returns `Typed.Type.t()`; impl returns a 2-tuple.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 19+20 | Phase 4 Typed internal-function specs — rewrite + visibility judgment [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | **Blocked on Task 45.** Read current impls, derive the true return types, rewrite both `@spec` lines (Task 19). If these really are internal, add `@doc false` — keeps the `@spec` for dialyzer but removes from generated docs. Then decide whether either fn is meant to be public API (Task 20); if so, adjust impl to match the documented intent instead of changing the spec. Judgment call; easier under fork ownership since we decide |
| 45 | `Cartouche.Typed` coverage push — exercise `encode_value_map/3` and `find_type/2` with representative inputs before rewriting their specs [D:2/B:2/U:3 → Eff:1.25] 📋 | ⬜ | Currently 94.44% (`mix test.json --cover` 2026-04-26). Gate for Tasks 19 + 20. The two specs being rewritten disagree with success typing; the rewrite needs tests of the actual return shapes (map vs bitstring for `encode_value_map/3`; `Typed.Type.t()` vs 2-tuple for `find_type/2`) so the new specs are grounded in observed behavior, not re-derived from reading the impl. Acceptance: both functions have ≥1 test exercising each return-shape branch |

---

## Phase 5: VM / Erc20.Call `none()` cascade investigation

**Why:** Four dialyzer `invalid_contract` warnings where success typing is `(_, _, _) -> none()`. `none()` means dialyzer believes the function cannot return normally — typically a cascade from an unreachable pattern, a `raise` on every traced path, or a macro-generated function dialyzer can't trace.

**Reach findings (pre-rename):**
- `mix reach.impact Cartouche.VM.exec/3` → **0 internal callers.** Only external consumers (onchain, downstream).
- `mix reach.impact Cartouche.Erc20.transfer/4` → **0 internal callers.** Same pattern.
- `mix reach.impact Cartouche.VM.exec_call/3` → ~37+ internal callers (autogenerated `Cartouche.Contract.IConsole.exec_vm_log_*`). Not the `none()` source.
- **Implication:** the `none()` cascade on these entry points is transitive — it propagates up from deeper callees where dialyzer's success-typing narrows (likely `Curvy`, `ABI`, `ExRLP`, or internal VM primitives that raise-on-error). Without internal call sites to constrain the top-level signature, dialyzer's whole-program typing collapses.

**What changes under fork ownership:** we can add `@dialyzer {:no_contracts, [exec: 3, transfer: 4]}` at the cartouche level instead of pushing onchain to carry the suppressions. Same cost; better locality.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 21+22 | Phase 5 `none()` cascade investigation + targeted fix or local suppression [D:5/B:4/U:5 → Eff:0.9] ⚠️ | ⬜ | **Blocked on Task 46.** Trace each Phase 5 warning back through `mix reach.deps` + `mix reach.slice` to find the first callee with `none()` success typing (Task 21, half-day to day). If root cause is a genuinely fixable spec narrowing, fix it; if it's structural (`raise`-heavy helpers), add `@dialyzer {:no_contracts, …}` locally in cartouche (Task 22). Local suppression is a valid terminal state |

---

## Phase 6: `Cartouche.VM.Context.init_from/2` spec

**Why:** `vm.ex:104 invalid_contract`. Spec says `:: t()` but success typing is the concrete struct literal, suggesting `@type t` is too loose or missing. Low-impact standalone.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 23 | Align `Cartouche.VM.Context.@type t` with dialyzer's inferred struct shape, or relax `init_from/2` to return `struct()` [D:2/B:1/U:3 → Eff:1.0] 📋 | ⬜ | **Blocked on Task 46.** Internal type. Bundle with Phase 5 if that opens a VM file anyway |
| 46 | VM + Erc20.Call coverage push — gate Phases 5 and 6 [D:4/B:5/U:5 → Eff:1.25] 📋 | ⬜ | Three modules below the bar (`mix test.json --cover` 2026-04-26): `Cartouche.VM.Context` 35.71% (Phase 6 target — 9 uncovered), `Cartouche.Erc20.Call` 0% (Phase 5 target — 6 uncovered), `Cartouche.VM.InvalidVm` 0% (1 uncovered, exception module — at minimum a `raise/rescue` round-trip; renamed from `VmError` in the credo cleanup pass). Cover `VM.Context.init_from/2` happy + edge inputs (the function whose spec Phase 6 narrows); cover `Erc20.Call` entry points used by the `none()`-cascade investigation in Phase 5. Acceptance: all three modules ≥ 80% on `mix test.json --cover` |

---

## Phase 7: Dependency freshness

Single-repo ownership simplifies this — we edit `mix.exs` and `mix.lock` directly, no dual-branch dance.

### 7.1 `google_api_cloud_kms` 0.38.1 → 0.43.0

`mix.exs` pins `~> 0.38.1` (resolves `< 0.39`). Cartouche uses this in `lib/cartouche/signer/cloud_kms.ex` via `cloudkms_..._get_public_key` and `cloudkms_..._asymmetric_sign`. Five minors of drift likely includes new key types (Ed25519, HMAC) or new methods worth surfacing.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 24+25 | Phase 7.1 `google_api_cloud_kms` 0.38.1 → 0.43.0 [D:3/B:3/U:4 → Eff:1.17] 📋 | ⬜ | Read CHANGELOG 0.38.1 → 0.43.0 — flag breaking changes to `get_public_key` / `asymmetric_sign`, and any new key types relevant to Ethereum signing or attestation (Task 24; release notes are dense, read every minor). Loosen constraint per findings; `mix deps.update google_api_cloud_kms`; verify `mix test` + `mix dialyzer.json` (Task 25) |
| 26 | Conditional feature-surface pass — expose Ed25519 / HMAC / new auth in a follow-up with docs + tests if Task 24 flagged anything relevant [D:5/B:4/U:4 → Eff:0.8] ⚠️ | ⬜ | Conditional on Task 24 findings |

### 7.2 `ex_doc` 0.31.1 → 0.40

`mix.exs` already carries `~> 0.40` (kept from the `:reach` requirement — `reach` pulls `makeup_elixir ~> 1.0` which conflicted with upstream's `ex_doc 0.31.1 → ~> 0.14`). No additional action needed beyond Task 4 verifying `mix docs` produces clean output.

### 7.3 `finch` 0.19 → 0.21

`mix.exs` pins `~> 0.19`. Cartouche uses Finch in `lib/cartouche/rpc.ex:167` and the error-normalizer in `util.ex:481`. Two minors of HTTP/2 and pool improvements — may simplify how we hand-build error strings from `%Finch.Error{}`.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 27+28 | Phase 7.3 `finch` 0.19 → 0.21 — audit + conditional adoption [D:2/B:3/U:4 → Eff:1.75] 🚀 | ⬜ | Read CHANGELOG 0.19 → 0.21; identify options relevant to `Finch.request/3` or error classification (Task 27). If concrete wins surface (cleaner error variants, better pool config, HTTP/2 telemetry), adopt with tests (Task 28) |

### 7.4 Lockfile refresh

`ex_sha3`, `goth`, `junit_formatter`: constraints already permit newer versions; just `mix deps.update` and verify. Bundle into any other dep PR to keep the diff tidy.

---

## Phase 8: `Cartouche.Transaction.V2.encode/1` duplication

**Why:** `mix ex_dna` surfaces one Type I (exact) clone in `lib/cartouche/transaction.ex`: both `encode/1` clauses of `Cartouche.Transaction.V2` (unsigned at line 394, signed at line 423) share 10 lines of identical struct destructuring and the same `<<0x02>> <> ExRLP.encode([...])` prefix. The signed clause differs only by appending the normalized `signature_y_parity` / `signature_r` / `signature_s` triple and applying `Enum.map/2` to the access list.

Natural extraction: a private helper returning the prefix list from the struct. Each clause either encodes that list as-is (unsigned) or concatenates the signature triple before encoding (signed).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 29+30 | Phase 8 V2 encode dedup — verify doctest coverage + extract helper [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Verify both encode clauses have doctest coverage; add one to the unsigned clause if missing (Task 29) — refactors without test coverage are risky. Then extract `defp unsigned_rlp_list/1`; rewrite both clauses to call it; verify byte-exact output equivalence via doctests (Task 30) |

**Do not run `mix ex_dna --literal-mode abstract` for refactor targets.** It finds near-misses that are often intentional (EIP version pairs, opcode groupings). Type I / exact duplication only.

---

## Phase 9: New transaction types + raw decode

**Why:** The three features that genuinely require cartouche internals. Under fork ownership these ship when ready — no review-cadence gating.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 31 | EIP-4844 blob transactions (`Cartouche.Transaction.V3`) — encode, sign, RLP round-trip, `max_fee_per_blob_gas` + `blob_versioned_hashes` fields [D:6/B:7/U:7 → Eff:1.17] 📋 | ⬜ | L2 rollups have posted blob txs since Dencun (Mar 2024). Include doctest + representative test vector from mainnet |
| 32 | EIP-7702 authorization-list transactions (`Cartouche.Transaction.V4`) — `authorization_list` field, tx type 0x04 [D:5/B:5/U:6 → Eff:1.1] 📋 | ⬜ | Smaller than Task 31. Active on mainnet since Pectra (May 2025) |
| 33 | Raw transaction decode — inverse of `Cartouche.Transaction.Vn.encode/1` across V1/V2/V3/V4 [D:4/B:4/U:6 → Eff:1.25] 📋 | ⬜ | Useful for mempool tooling, explorers. The existing surface feels incomplete without it |

---

## Phase 10: Upstream PR candidates (to `hayesgm/signet`)

**On-demand only.** We ship fixes in cartouche first. A task from a prior phase becomes an upstream-PR candidate once it's proven in cartouche and the PR would be clean, single-concern, and helpful to existing signet users.

### PR style (observed in signet's `git log`)

Narrow, single-concern, lowercase conventional-commit subject (`fix:`, `chore:`, `feat:`). One module, one behaviour per PR. Match the shape. Recent merged examples on signet: #119, #121, #126.

### Candidates

| Source | Nature | Upstream value |
|--------|--------|----------------|
| Phase 1.1 — `RecoveryBit` `:no_return` typo (landed here 2026-04-25 under Task 38) | `fix:` | Pure win; no runtime effect; one line. Port the spec fix only — `Cartouche.Util.RecoveryBit` still exists upstream |
| Phase 1.2 — `to_wei/1` narrow return | `chore:` | Pure win; one line |
| Phase 1.3 — `Signer.sign_direct/4` `mfa()` | `fix:` | Real type mismatch; one line + doctest |
| Phase 1.4 — `Cartouche.Hex` return specs | `fix:` | Four specs + doctests; evidence grounded in dialyzer output |
| Phase 2 — RPC error-shape widening | `fix:` | Evidence grounded; multiple shapes documented |
| Phase 3 — Trace/TraceCall deserialize specs | `fix:` | Evidence grounded |
| Phase 4 — Typed internal-function specs | `fix:` | Judgment call per Task 20 — pitch once we've decided direction |
| Phase 7.1 — `google_api_cloud_kms` constraint bump | `chore:` | Pitch only if it surfaces a concretely useful newer feature; otherwise maintainers refresh constraints on their own cycle |
| Phase 8 — V2 encode dedup | `refactor:` | Judgment call. Maintainer may prefer parallel clauses for EIP-1559 auditability. Disarming tone in PR body; happy-to-close framing |

### Not candidates

- Phase 0 (release mechanics — cartouche-specific)
- Phase 5 (cascade work — terminal state is local `@dialyzer` suppression)
- Phase 6 (VM-internal — low signet value)
- Phase 9 (new tx types — ship in cartouche first; reconsider upstream once production-tested, if signet is still active)

### Upstream PR checklist

Before opening any PR to `hayesgm/signet`:

1. Fix has landed in cartouche and survived at least one `0.1.x` release.
2. Port the fix to a branch off signet's `main` (separate working copy — our `development` branch has cartouche-specific tooling like `dialyxir`, `sobelow`, etc., that signet lacks).
3. Verify `mix format --check-formatted` + `mix test` pass on signet's vanilla setup.
4. PR body cites the cartouche commit / release where the fix has been running.
5. Include doctest evidence for any spec change.
6. No bundling. One concern per PR.

### External package — `ABI.decode/2` spec in `poanetwork/ex_abi`

| # | Task | Status | Notes |
|---|------|--------|-------|
| 34 | `ABI.decode/2` specced `no_return()` in `poanetwork/ex_abi` [D:3/B:5/U:5 → Eff:1.67] 🚀 | 🔶 | Separate fork + PR if pursued. Only chase if Phase 1 fixes are merged (here) and onchain's remaining dialyzer noise is clearly bounded by this |

---

## Completed

_None yet beyond `0.0.1` placeholder (see [CHANGELOG.md](CHANGELOG.md))._

---

## Audit provenance

Findings that drive Phases 1–8:

- `mix dialyzer.json --quiet --output /tmp/cartouche-dialyzer.json` (2026-04-21, pre-rename) — 11 `invalid_contract` warnings drove Phases 1.3, 1.4, 3, 4, 5, 6.
- `mix hex.outdated` (2026-04-21) — drove Phase 7.
- `mix ex_dna` (2026-04-21) — one Type I clone drove Phase 8 (41 files analyzed, 1 clone, ~28 duplicated lines).
- `mix reach.hotspots` + `mix reach.coupling` + `mix reach.impact` (2026-04-21, reach 1.6.0) — confirmed Phase 2 blast radius (32 callers, 6 direct breakage points, MEDIUM risk); downgraded Phase 5 after discovering `VM.exec/3` and `Erc20.transfer/4` have 0 internal callers; identified pervasive `Cartouche.VM` submodule cycles likely feeding the cascade.
- Manual audit of `lib/cartouche/rpc.ex` + `lib/cartouche/util.ex` + `lib/cartouche/signer/cloud_kms.ex` — drove Phases 1.1, 1.2, 2, 7.1.

Before starting Phase 1 work, re-run `mix dialyzer.json --quiet --group-by-file` on the current `development` branch to catch any regressions introduced during the signet → cartouche rename.

---

## Consumer re-probe (onchain)

Once cartouche `0.1.0` is on hex and onchain flips `mix.exs` from `signet` to `cartouche`:

```bash
cd ../onchain
mix deps.update cartouche
mix dialyzer.json --quiet
# strip @dialyzer {:no_match, …} blocks from Onchain.Hex / ABI / Contract / ERC / ENS / Multicall
# as each of Phase 1.4 / Phase 2 fixes lands in a cartouche release
```

See `onchain/ROADMAP.md` for the full strip checklist.

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

## Delegation Markers

- `[CX]` — Codex Cloud-eligible (no internet, no Tidewave, no dep changes — see `~/.claude/includes/task-prioritization.md`)
- `[CSR]` — Cursor Background Agent-eligible (broader: hex.pm + mix tasks runnable)
- `[P]` — parallel-eligible (orthogonal to delegation)
- _no marker_ — local only (needs Tidewave / dep change / cross-repo coordination)

Local sessions: do **not** execute `[CX]` / `[CSR]` rows unless explicitly redirected (per `critical-rules.md` § "DON'T STEAL CLOUD-AGENT-DELEGATED TASKS").

---

## 🎯 Current Focus

**INE-17 / Phase 11 decode-struct atom audit corrected 2026-05-05.** Verified the generator emits return-field names as strings inside selector metadata, not compile-time atoms; both live `decode_structs: true` paths now explicitly pre-intern bounded ABI field atoms before calling Hieroglyph 1.4.0's `String.to_existing_atom` decoder. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**`cartouche 0.1.3` cut 2026-05-02.** Phase 7.1 dep refresh — `google_api_cloud_kms` 0.38.1 → 0.43.0, internalising the 0.40 breaking arity change in both KMS signers behind a private `key_version_name/5` helper while preserving public API of `Cartouche.{Signer,Solana.Signer}.CloudKMS` (Tasks 24+25, 26 superseded). Phase 7.4 lockfile refresh closed Tasks 71 (`junit_formatter` 3.4.0 pin loosen) and 72 (`bandit` 1.11.0 lock-only). See [CHANGELOG `[0.1.3]`](CHANGELOG.md#013--2026-05-02).

**`cartouche 0.1.2` cut 2026-05-01.** Dep refresh + `mix.exs` pin tightening — picks up `hieroglyph 1.4.0` (atom-table DOS guard on `decode_structs: true`, plus the silent bug-fix windfall in 1.0.0–1.2.0), `ex_dna 1.4.3`, `ex_ast 0.8.1`. Pin `hieroglyph: "~> 1.4"` raises the consumer floor to match what cartouche is now tested against. See [CHANGELOG `[0.1.2]`](CHANGELOG.md#012--2026-05-01).

**`cartouche 0.1.1` cut 2026-05-01** (superseded same day by 0.1.2 before hex publish). Bundled the Block decoder fork fields (Tasks 63 + 64 + 65) and the two wire-format bugs the new mainnet integration suite (Task 61) caught at first run — `get_block_by_hash/2` missing `fullTransactionObjects` and V1 empty-calldata encoded as `"0x0"` instead of `"0x"`. Both pre-existing in upstream signet for years, masked by the mock client. See [CHANGELOG `[0.1.1]`](CHANGELOG.md#011--2026-05-01).

**Phase 0 fully closed 2026-04-30 — `cartouche 0.1.0` shipped.** First active release under the cartouche namespace. The downstream onchain `@dialyzer {:no_match}` strip across `Onchain.Hex` / ABI / ERC / ENS / Multicall callers is now load-bearing — Phase 1 spec corrections (1.1 RecoveryBit, 1.2 Wei, 1.3 Signer, 1.4 Hex) all in `0.1.0`.

**Block decoder bundle (Tasks 63 + 64 + 65) shipped in `0.1.1`.** `Cartouche.Block` extended with seven Ethereum-hard-fork fields (`base_fee_per_gas` London; `withdrawals_root` + `withdrawals` Shanghai; `parent_beacon_block_root` + `blob_gas_used` + `excess_blob_gas` Cancun; `mix_hash` pre/post-Merge). Nested `Cartouche.Block.Withdrawal` substruct mirrors the `Receipt.Log` precedent. Integration tests at the post-London 15M, post-Shanghai 18M, and post-Cancun 20M anchors strengthen from `refute Map.has_key?/2` → positive assertions. `Cartouche.Block` + `Cartouche.Block.Withdrawal` both at 100% coverage; dialyzer clean on `block.ex`; total `invalid_contract` count holds at 8.

**Mainnet integration suite (Task 61) shipped in `0.1.1`.** `test/rpc_integration_test.exs` opts in via `mix integration` and pins behaviour against historical mainnet anchors via the local archive-node SSH tunnel. Decoder gaps surfaced as Tasks 62 (traces), 63–65 (Block fork fields, ✅ shipped in `0.1.1`), 66 (Block.transactions full details), 67 (Receipt blob fields, ✅ shipped under `[Unreleased]`). Task 68 (originally "DebugTrace EIP-7702 opcodes") closed obsolete 2026-05-01 — premise wrong (AUTH/AUTHCALL were EIP-3074, withdrawn; EIP-7702 introduces no new opcodes); replaced by Task 70 (CLZ for Osaka, blocked on activation).

Highest-Eff unblocked candidates after the Block bundle: Tasks 14+15+35 (RPC error-shape widening + `Jason.encode!` rescue, Eff:1.75), Task 27+28 (Finch 0.19→0.21, Eff:1.75), Task 44 (Generator coverage push, gates Tasks 41/42/50/59-gen, Eff:1.67).

**Phase 12 (descripex adoption) opens 2026-05-04.** New phase below — exposes cartouche's API surface to AI agents via `descripex` annotations + a static manifest. Bootstrap (Task 82) is the gate; once it lands, Tasks 83-88 are six `[P]`-eligible annotation passes that can run in parallel sessions, and Task 89 wires the manifest export. Highest-Eff individual annotation candidate: Task 83 (Signer + Keys, Eff:2.0); largest single-task surface: Task 84 (RPC + 6 response decoders, 7 modules total).

---

## 📦 Recommended bundles

Tasks below ship more efficiently together. Bundling rationale: same module(s), same coverage gate, sequential dependency where one's prep step *is* the other's prerequisite, or a single regenerate/recompile round-trip that would otherwise be paid multiple times.

D/B/U scores stay on individual rows — bundling is about session ergonomics, not re-pricing. The compound-ID convention (`7+8+9`, `10+11+12+13`, `14+15+35`, etc.) already covers tightly-coupled bundles that share one ROADMAP row; the table below documents the looser sets that retain their individual rows.

| Bundle | Tasks | Why bundle |
|---|---|---|
| **Generator hardening pass** | 44 → 41 + 42 + 50 (+ 59-gen sub-items) | 44 is the coverage gate for 41 (bytecode-flag separation) and 42 (`decode_error` dead branch). Once 41 + 42 fix the templates, 50 emits `@doc`/`@spec` on the same regenerated bindings — and 59's four `lib/mix/cartouche.gen.ex` items (`module_name`/`List.flatten` dead binds, two `Macro.underscore/1` repeats) ride along. One IConsole regeneration round-trip instead of three; `.dialyzer_ignore.exs` and `.doctor.exs ignore_paths` both retire when the bundle ships. Heaviest bundle — recommend pause-for-`/compact` after Task 44 (coverage push) lands; second batch covers 41 + 42 + 50 + 59-gen + IConsole regenerate together |
| **Typed cleanup** | 45 → 19+20 | 45 raises `Cartouche.Typed` coverage to 100% by exercising `encode_value_map/3` and `find_type/2` with representative inputs — the tests that ground 19+20's spec rewrite are produced by the coverage push itself. Splitting wastes a session reading the same impl twice |
| **VM dialyzer cleanup** | 46 → 21+22 + 23 | 46 raises coverage on `Cartouche.VM.Context`, `Cartouche.Erc20.Call`, `Cartouche.VM.InvalidVm` — exactly the territory the `none()` cascade investigation (21+22) and the `VM.Context.@type t` alignment (23) need to reason about. Single VM mental model, one `mix dialyzer.json` baseline run, three modules |
| **KMS upgrade chain** | 24+25 → 26 | 26 is conditional on the 0.38.1 → 0.43.0 changelog audit performed in 24+25. Same `mix.exs` edit, same `mix deps.update` round-trip; if the audit finds nothing new worth surfacing, 26 closes immediately as superseded. Splitting forces a second deps session |
| **Phase 7 dep refresh** | 24+25 + 26 + 71 + 72 | Single `mix.exs` edit, single `mix deps.update`, single `mix test.json` + `mix dialyzer.json` round-trip. KMS audit (24+25) is the bulk; 71 + 72 ride along; 26 likely closes as superseded (Ed25519 shipped via Solana). Critical-tier coverage gate on both KMS signer modules — verify ≥95% before any code mutation triggered by the audit |
| **Sleuth hardening** | (raise `Cartouche.Sleuth` to ≥95% coverage) → 48 | Internal bundle — Task 48's note already mandates the coverage push before the `String.to_atom` → `String.to_existing_atom` swap (per `critical-rules.md` "RAISE COVERAGE BEFORE MUTATING", Sleuth is critical-tier). Track as one delivery; the coverage step does not warrant its own task ID |
| **Descripex adoption** | 82 → 83 + 84 + 85 + 86 + 87 + 88 → 89 | Task 82 stands up the wrapper + validation test. Tasks 83-88 are independently `[P]`-eligible — different sessions can annotate Signer / RPC / Transaction / Solana stack / utilities in parallel. Each pairs a primary entry point with its small co-domain helpers (so each annotation session covers one mental-model cluster, no module reopens). Task 89 closes once all 83-88 land. Recommend pause-for-`/compact` after the bootstrap (Task 82) lands, then a second batch covering 1-2 of the larger `[P]` annotation tasks per session (Task 84 is the largest at 7 modules; 87 and 88 each cover 9 modules). Smaller `[P]` tasks (83 with 2 modules, 86 with 1 module) bundle freely |

### Already bundled (compound IDs)

`7+8+9` Phase 1.1–1.3 ✅ · `10+11+12+13` Phase 1.4 Hex ✅ · `14+15+35` RPC error shapes · `16+17+18` Trace specs ✅ · `19+20` Typed specs · `21+22` VM cascade · `24+25` KMS ✅ · `27+28` Finch · `29+30` V2 dedup · `71+72` junit_formatter + bandit lock refresh ✅ · `83/84/85/86/87/88` Phase 12 annotation `[P]` set.

### Standalone (no natural bundle partner)

`6` (publish, user-only) · ~~`39` (RecoveryBit doctest portability)~~ ✅ · ~~`47` (config-only — exclude IConsole from coverage measurement)~~ ✅ · ~~`54` (Transaction.Call extraction — large, structural, spans generator + RPC + Sleuth)~~ ✅ · ~~`58` (single test)~~ ✅ · `59-lib` (Reach 1.8 hygiene items in `lib/cartouche/**` — the `solana/transaction.ex`, `hex.ex`, `transaction.ex`, `rpc.ex` redundant-computation extractions; distinct from the gen.ex sub-items which roll into the Generator hardening pass) · `31` (EIP-4844) · ~~`32` (EIP-7702)~~ ✅ · `33` (raw decode — sequenced *after* 31 + 32 so it inherits the encoded forms).

---

## Phase 0: Ship `0.1.0`

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Reset `mix.exs` version `1.6.1` → `0.1.0-dev` [D:1/B:3/U:7 → Eff:5.0] 🎯 | ✅ | Done 2026-04-24 |
| 2 | Full `mix test.json --quiet` pass on the ported code [D:3/B:5/U:7 → Eff:2.0] 🚀 | ✅ | 665 passed / 0 failed on 2026-04-24. Also cleared two stale test warnings (`test/support/vm_test_helpers.ex:11` missed by C1 pin sweep, `test/solana/pda_test.exs:137` underscored-then-used var) |
| 3 | `mix dialyzer.json --quiet` — inventory remaining `invalid_contract` warnings, confirm they match the pre-rename audit (Phases 1, 3, 4, 6 below) [D:2/B:3/U:6 → Eff:2.25] 🚀 | ✅ | 2026-04-24: 11/11 `invalid_contract` accounted for; total 1,626 matches the post-abi-fix benchmark. Phase 1.4 scope narrows to `from_hex/1` only (see Phase 1.4 note below) |
| 4 | `mix docs` clean build with cartouche branding intact [D:2/B:3/U:5 → Eff:2.0] 🚀 | ✅ | Done 2026-04-24; `doc/index.html`, `doc/llms.txt`, `doc/Cartouche.epub` all build; `llms.txt` header reads `Cartouche v0.1.0-dev`; 54 `Cartouche.*` entries in `api-reference.html`; only `signet`/`hayesgm` hits in `doc/` are the README attribution links. Pre-existing ex_doc type-ref warnings split out as Task 36 |
| 5 | Update `README.md` installation section — replace the "not recommended yet" placeholder with real install instructions [D:1/B:3/U:7 → Eff:5.0] 🎯 | ✅ | Done 2026-04-25 as part of Task 37 prep. Status block + install snippet activated |
| 6 | Tag `0.1.0`, publish to hex [D:1/B:5/U:8 → Eff:6.5] 🎯 | ✅ | Done 2026-04-30. `cartouche 0.1.0` live on hex.pm — first active release under the cartouche namespace. Phase 0 fully closed. Onchain `@dialyzer {:no_match}` strip on `Onchain.Hex` / ABI / ERC / ENS / Multicall callers becomes load-bearing now |
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
| 41 | Generator bytecode-flag separation — init vs deployed `[CX]` [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | **Blocked on Task 44.** `Mix.Tasks.Cartouche.Gen.build_module/3` derives a single `has_bytecode` flag from `not Enum.empty?(bytecode_decl)` (init bytecode) and threads it through `get_encode_calls/2`, `encode_function_call/3`, `abort?/3`, and `select_emitted_fns/3`. But the `:pure` branch's `exec_vm_fn` uses `deployed_bytecode/0` while the constructor branch uses `bytecode/0` — different flags belong on different gates. Asymmetric artifacts (init bytecode present but deployed absent, or vice versa) currently misbehave: the first emits `exec_vm_*` referencing undefined `deployed_bytecode/0` → `CompileError` at consumer load; the second skips `exec_vm_*` even though the runtime would have worked. Pre-existing in upstream; preserved by Task 40's refactor. Trigger probability is low (Hardhat/Foundry always pair both bytecodes), so deferred from the Task 40 commit. Fix shape: add `has_deployed_bytecode` alongside `has_bytecode`, gate `:pure`'s `exec_vm_*` on the deployed flag, gate constructor `abort?` on the init flag. Add regression tests for both asymmetric shapes. Discovered during the Task 40 staged review |
| 42 | Generator `decode_error/1` template — drop dead `if true ... else ... end` branch [D:1/B:1/U:2 → Eff:1.5] 📋 | ✅ | Done 2026-05-04. Collapsed `lib/mix/cartouche.gen.ex:186-197` from the dead-branch fallback to `def decode_error(_), do: :not_found` (matches the `decode_call/1` / `decode_event/2` shape immediately above). `decode_call/1` (`:181`) and `decode_event/2` (`:201`) were already in the correct form — only `decode_error` carried the dead branch. Regenerated `lib/cartouche/contract/{i_console,sleuth}.ex` via `mix cartouche.gen --prefix cartouche/contract ./sol/out/IConsole.sol/IConsole.json` and `... ./priv/Sleuth.json`. Bundled with INE-10 / PR #8 (Cursor-extracted `Cartouche.Transaction.Call`) because the regenerated bindings are needed to drop the dead-branch warnings that block the CI harness's `mix dialyzer` step. Coverage gate met by Task 44 / coverage on `Mix.Tasks.Cartouche.Gen` (73.06%, below standard tier — flagged below; the trivial template collapse is exempt under the `critical-rules.md` "RAISE COVERAGE BEFORE MUTATING" rename-only carve-out, but Task 44's broader push remains open). Closes Task 42 |
| 44 | Generator coverage push — raise `Mix.Tasks.Cartouche.Gen` to ≥80% before Tasks 41 + 42 `[CSR]` [D:3/B:4/U:6 → Eff:1.67] 🚀 | 🔄 in-flight (INE-20) | 📦 **Generator hardening bundle entrypoint** — chain into 41 + 42 + 50 + 59-gen sub-items in one session. Currently 73.05% (69 uncovered lines per `mix test.json --cover` 2026-04-26). Gate for Tasks 41 (bytecode-flag separation) and 42 (`decode_error` dead branch). Cover `build_module/3` happy + asymmetric-bytecode shapes, `get_encode_calls/2` fallback emitter, `encode_function_call/3` per-arity branches, `abort?/3` true/false paths, `select_emitted_fns/3` selection logic, and the `decode_error/1` / `decode_call/1` / `decode_event/2` template fallbacks. Use a tiny synthetic ABI fixture rather than regenerating IConsole. Acceptance: `Mix.Tasks.Cartouche.Gen` ≥ 80% on `mix test.json --cover` |
| 47 | Exclude generated `Cartouche.Contract.IConsole` from coverage measurement [D:1/B:1/U:3 → Eff:2.0] 🚀 | ✅ | Done 2026-05-02. Added `mix.exs` `test_coverage: [ignore_modules: [Cartouche.Contract.IConsole]]` to exclude the generated IConsole binding from headline coverage while leaving other modules unchanged. Verification commands for local/dev CI: `mix test.json --cover --quiet --output /tmp/cov.json`, `jq -r ' .coverage.modules[].module ' /tmp/cov.json | rg Cartouche.Contract.IConsole`, `mix test.json --quiet`. |
| 49 | ~~Resolve `Cartouche.Transaction.V2.encode/1` spec duplication~~ — **superseded by Task 54** | 🔶 | **Folded into Task 54.** The narrow `V2.encode/1` spec union targeted here is obsoleted by the structural `Cartouche.Transaction.Call` extraction — widening `V2.t()` signature fields to nullable is the surface symptom; Call extraction fixes the abstraction boundary that drives the symptom. Doing both is wasted work. Closing as duplicate of Task 54 |
| 54 | ~~Extract `Cartouche.Transaction.Call` — collapse the V2-as-eth-call-shape lie~~ `[CSR]` [D:6/B:5/U:5 → Eff:0.83] ⚠️ | ✅ | Done 2026-05-04 (PR #8 / INE-10). New `Cartouche.Transaction.Call` struct emitted by `Cartouche.Contract.Sleuth.build_trx_query/3`; RPC dispatch widened to `V1.t() \| V2.t() \| Call.t()`. Sleuth dialyzer cascade collapses. See [CHANGELOG.md](CHANGELOG.md#unreleased). **Replaces Task 49.** Generator-emitted `Cartouche.Contract.Sleuth.build_trx_query/3` (`lib/cartouche/contract/sleuth.ex:33`) returns `%V2{destination: contract, data: encode_query(q, c)}` — partial-struct (2 of 12 fields populated). `V2.t()` (`lib/cartouche/transaction.ex:232–245`) declares all 12 fields non-nullable. Dialyzer correctly identifies a contract violation; the cascade surfaces as `no_return` + `invalid_contract` warnings in `Cartouche.Sleuth` (`lib/cartouche/sleuth.ex` — the hand-written wrapper) propagating through `Sleuth.call_query → Sleuth.query_internal/5` to the public Sleuth entrypoints. Runtime is fine because `Cartouche.RPC.to_call_params/2` (`rpc.ex:1533–1553`) tolerates the nils via `nil_map/2` (`rpc.ex:1607`); `call_trx/2` (`rpc.ex:298`) routes through it. **The fix is structural, not a spec widening.** Eth_call params are not transactions — never signed, never broadcast, only executed. The current `%V2{}` masquerade is the abstraction lie. Define `defmodule Cartouche.Transaction.Call do` with at minimum `destination: <<_::160>>, data: binary()` (audit `RPC.to_call_params/2` to determine if `value` / `gas` / `from` should also be Call-shape fields). Update the generator template (`lib/mix/cartouche.gen.ex` `build_trx_*` quote blocks) to emit `%Call{}` instead of `%V2{}`. Extend RPC dispatch to accept `V1.t() \| V2.t() \| Call.t()`. Regenerate `Cartouche.Contract.IConsole` and `Cartouche.Contract.Sleuth`. **Fix scope spans two modules:** the generator template (origin of the `%V2{}` masquerade emitted into `lib/cartouche/contract/sleuth.ex`) and `Cartouche.Sleuth` (where the cascade surfaces). **Out of scope (separate task if pursued):** Unsigned/Signed split for V1/V2 — Codex flagged the third rail (RLP/signing/recovery), and that refactor would inflate this task significantly without addressing the Sleuth cascade. **Coverage gate:** `Cartouche.RPC`, `Cartouche.Transaction`, generator (Task 44 already gates this), and consumer test suite. Critical-tier modules touched. Audit before mutating. Acceptance: the Sleuth dialyzer cascade collapses; `mix test.json --quiet` green; round-trip tests for both V2 transactions (signed) and Call shapes (eth_call); narrow `.dialyzer_ignore.exs` entries (the two generated files) unchanged because the underlying type contract is now honest. Discovered + scoped during Codex consultation 2026-04-26 |
| 50 | Generator emits `@doc`/`@spec` on generated bindings — drop `.doctor.exs` `ignore_paths` `[CX]` [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Natural co-deliverable with Task 42 (template fix → IConsole regeneration). `Mix.Tasks.Cartouche.Gen` currently emits no `@doc` or `@spec` on the functions it builds (`encode_*`, `decode_*`, `*_selector`, `call_*`, `estimate_gas_*`, `call_log_*`, `exec_vm_*`, etc.). The doctor-driven typespec sweep (2026-04-26) hit this and had to add `.doctor.exs` `ignore_paths: [~r"^lib/cartouche/contract/"]` to suppress the resulting flood of missing-doc/spec warnings (Doctor doesn't currently see them with the path-exclude in place). Fix shape: extend each `def unquote(name)(args)` block in the generator's `quote do ... end` templates to attach a `@doc` (one-liner derived from ABI metadata — function name, signature, brief purpose) and a `@spec` (derived via existing ABI type → Elixir type mapping). Once Tasks 41/42/44 land and IConsole is regenerated, this becomes a small marginal additional template change. Acceptance: regenerated `lib/cartouche/contract/i_console.ex` (and other bindings) carry `@doc` + `@spec` on every public function; `.doctor.exs` `ignore_paths: [~r"^lib/cartouche/contract/"]` removed; `mix doctor` clean. Discovered during the staged review of the typespec sweep |
| 48 | Harden `Cartouche.Sleuth` atom-table risks `[CSR]` [D:5/B:4/U:5 → Eff:0.9] ⚠️ | ⬜ | 📦 **Sleuth hardening bundle** — coverage push to ≥95% + atom-swap, internal bundle, one delivery. The INE-17 fix removed the new runtime-selector preinterning `String.to_atom/1` finding from this task by switching that path to `String.to_existing_atom/1` and surfacing a helpful decode error when dynamic selectors reference cold field atoms. Remaining risk: the `query_by/3` atom-deriving pair and `name_keyword/1` still mint atoms lazily at runtime and remain accepted-pending-fix in `.sobelow-skips` (current fingerprints `13012D4`, `536511`, `4A9C581`; historical line-shift predecessors `30CD86E`, `44BAAB1`, `106E34D`, `1E4D9BF`, `5A84B72`, `1754556`). Fix shape: keep the ≥95% `Cartouche.Sleuth` gate, swap remaining runtime mints to `String.to_existing_atom`, and raise on missing atom. Discovered during the DebugTrace audit (2026-04-26 hardening, see CHANGELOG `[Unreleased]`) |
| 55 | Harden `Cartouche.Trace.deserialize/1` against missing/nil `traceAddress` [D:1/B:2/U:3 → Eff:2.5] 🎯 | ✅ | Done 2026-04-29. Replaced `Enum.map(params["traceAddress"], &decode_address_or_number/1)` at `lib/cartouche/trace.ex:423` with a private `decode_trace_address/1` helper (`is_list/1` clause maps; fallback raises `ArgumentError, "missing traceAddress in trace_transaction result element"`) so missing/`nil` `traceAddress` now fails loudly at the boundary instead of crashing `Protocol.UndefinedError` from inside `Enum.map`. The Task 51 audit (Codex dialogue 2026-04-26 vs OpenEthereum + Infura `trace_transaction` schemas) confirmed `traceAddress` is mandatory on the wire — the root call shows `[]`, not omission — so the right contract is loud-reject, not soft `|| []`. New `describe "deserialize/1 — traceAddress absent/nil (Task 55)"` block in `test/trace_test.exs` pins both the missing-key and explicit-nil shapes via `assert_raise ArgumentError, ~r/missing traceAddress/`. `TODO(Task 55)` marker dropped. `Cartouche.Trace` coverage stays at 100%; full suite green (778/778); dialyzer clean on `trace.ex`. Closes Task 55 |
| 43 | Pre-credo coverage push for cleanup-target modules [D:3/B:5/U:7 → Eff:2.0] 🚀 | ✅ | Done 2026-04-26. Raised test coverage on the six modules slated for credo-strict cleanup so the refactor session can rename / restructure / silence flags safely. New blocks landed in `test/assembly_test.exs` (data-driven `show_opcode/1` table covering every named-atom arm + PUSH/DUP/SWAP/INVALID tuple coverage, multi-arity `compile/1` 3–7, `transform_jumps` missing-jump-dest path, full PUSH1–32 / DUP1–16 / SWAP1–16 / 0xfe `disassemble_opcode/1`, per-clause `opcode_size/1`, `constructor/1` wrap, exception-struct defaults), `test/receipt_test.exs` (contract-creation receipt with `to: nil`/`contractAddress` populated; log shapes for empty data / 2-topic / 4-topic), `test/open_chain_test.exs` (TestClient extended with magic-byte signature dispatch for `ok=false` / non-JSON / transport-error / multi-result / empty paths; `lookup_error` / `lookup_error_and_values` short-binary clauses; `Signatures.deserialize/1` filter behavior), `test/transaction_test.exs` (`V2.new/9` chain-id-nil fallback, `V2.new/12` nil fee fields, `build_trx_v2` ABI-tuple + raw-binary call-data, `build_signed_trx_v2` happy-path with signer-recovery roundtrip + callback short-circuit, `V2.decode` malformed-RLP body), `test/sleuth_test.exs` (try-apply rescue with descriptive `RuntimeError` when the contract module is missing `bytecode/0`), and `test/solana/signer_test.exs` (explicit cache-hit test with `:sys.get_state/1` confirming the `:address` key is populated after the first call). Bundled with the coverage work: bug fix in `lib/cartouche/open_chain.ex:200` — `Enum.join(found_signatures, ",")` over a list of `{sig, name}` tuples replaced with `Enum.map_join(found_signatures, ",", fn {_, name} -> name end)`. Was crashing `Protocol.UndefinedError` instead of returning `{:error, "Multiple matching signatures: ..."}` on the `raise_on_multiple: true` path. Surfaced while writing the test for the multi-result error path; per `critical-rules.md` "NEVER HIDE TEST FAILURES" the test now asserts the corrected return shape (including the actual signature names) rather than pinning the broken raise |
| 57 | Fix `Cartouche.Solana.Transaction.sign_partial/2` zero-signer boundary [D:1/B:3/U:3 → Eff:3.0] 🎯 | ✅ | Done 2026-04-27 (bundled with Task 56). Appended `//1` step to the range at `lib/cartouche/solana/transaction.ex:415` — `0..(num_signers - 1)//1` yields `[]` when `num_signers == 0` and is behaviour-preserving for `num_signers >= 1`. New ExUnit `describe "sign_partial/2 — zero-signer boundary (Task 57)"` block asserts `signatures == []` for a synthetic 0-signer message (real Solana txs always have ≥1 fee payer; the test exists purely to pin the boundary against future regression) |
| 58 | ~~Strengthen `Cartouche.Filter` expired-filter test — assert recovery-branch fingerprint~~ `[CX]` [D:1/B:2/U:2 → Eff:2.0] 🚀 | ✅ | Done 2026-05-05 (PR #16 / INE-15). Test now asserts `Process.get(:expired_seen) == true` and `Process.get(:new_filter_count) >= 2` after the receive asserts, pinning the recovery branch by fingerprint. See [CHANGELOG.md](CHANGELOG.md#unreleased). **Rescoped 2026-05-04** — original framing referenced a `# TODO(Task 58): Test expired filter` comment at `test/filter_test.exs:53`. That premise was stale: line 53 is `:timer.sleep(600)`, no TODO marker, `grep TODO(Task 58)` across `lib/` and `test/` returns zero matches, and the expired-filter test already exists at lines 84–120 (`test "recreates filter when ethereum node reports expired filter"`) with the `ExpiredFilterClient` mock at lines 9–36. Real gap: the mock at `:27` sets `Process.put(:expired_seen, true)` when the `-32000 "filter not found"` branch fires, and `:18–23` increments `:new_filter_count` on each `eth_newFilter` call, but the test only asserts `assert_receive {:event, _}, 500` + `assert_receive {:log, _}, 500` — neither flag is read back. The recovery branch is exercised in practice (mock uses different filter ids — `0xf11735` returns the error, `0xf11736` returns valid data — so the test fails if recovery doesn't fire), but a future implementation that silently retried on the same filter id and somehow satisfied the receive contract would still pass. Strengthen the existing test by adding `assert Process.get(:expired_seen) == true` and `assert Process.get(:new_filter_count) >= 2` after the receive asserts. Verify mock semantics first by reading `lib/cartouche/filter.ex` `handle_info` for the expired-filter recreate branch (per `critical-rules.md` "NEVER HIDE TEST FAILURES" — don't pin against broken behavior). **Out of scope:** the `:timer.sleep(600)` cleanup at `filter_test.exs:52` (different test, optional follow-up), additional error-code coverage (separate gap if needed), and any `lib/cartouche/filter.ex` mutation (test-strengthening only). Pre-implementation: `Cartouche.Filter` coverage check (test-only addition is exempt from the ≥80% mutation gate). Discovered 2026-05-04 |
| 59 | Reach 1.8 hygiene pass — redundant computations + suspicious dead binds `[CSR]` (split candidate: lib/cartouche/** items are `[CX]`) [D:1/B:2/U:1 → Eff:1.5] 📋 | ⬜ | 📦 **Splits across two bundles:** `lib/cartouche/**` items run standalone (no gate); `lib/mix/cartouche.gen.ex` items roll into the **Generator hardening bundle** (with 44 + 41 + 42 + 50). `mix reach.smell` + `mix reach.dead_code` (reach 1.8.0, run 2026-04-28) surfaced a small cluster of behavior-preserving cleanups. Redundant computations — dedupe by extracting a local: `lib/cartouche/solana/transaction.ex:201–202` (`length/1` called twice on the same arg), `lib/cartouche/hex.ex:353–354` (`byte_size/1` twice), `lib/cartouche/transaction.ex:512–513` (same binary literal built twice), `lib/cartouche/rpc.ex:193,195` (`inspect/1` twice across an interpolated log line). Dead binds in `lib/mix/cartouche.gen.ex:816` (`module_name = String.to_atom(...)` value never read) and `:817` (result of `List.flatten/1` discarded) — investigate before deleting; an unused result in the generator may indicate an unfinished branch, not pure dead code. Two `Macro.underscore/1` repeats in the same generator (`:353–354`, `:396–397`) bundled here. **Coverage-gate caveat:** `Cartouche.Hex` and `Cartouche.Transaction` are critical-tier (≥95%); `Mix.Tasks.Cartouche.Gen` items are gated on Task 44 (≥80% generator coverage push) — these refactors hover near the "pure rename" exemption but extracting to a local technically mutates the AST, so verify each touched module is at tier via `mix test.json --cover` before changing, or split the gen.ex items off and let Task 44 land first. Acceptance: re-run `mix reach.smell` and `mix reach.dead_code` — listed locations drop out; `mix test.json --quiet` green; no new dialyzer warnings on the touched modules. Discovered while updating the global `reach.md` include for reach 1.8 (2026-04-28) |
| 60 | ~~`Cartouche.RPC.get_block_by_number/2` integer path crashes on real nodes~~ [D:1/B:3/U:4 → Eff:3.5] 🎯 | ✅ | Done 2026-04-28. Public `Cartouche.Hex.encode_quantity/1` + a private `normalize_block_param/1` helper in `Cartouche.RPC` applied at all 10 block-tag-forwarding callsites (`get_block_by_number/2`, `get_nonce/2`, `call_trx/2`, `estimate_gas/2`, `get_code/2`, `get_balance/2`, `get_transaction_count/2`, `trace_call/3`, `trace_call_many/2`, `debug_trace_call/2`). Wire-format integration test via `CaptureClient` test double in `test/rpc_test.exs`. README chain restored to `eth_block_number → get_block_by_number(int)` alongside the `"latest"` form. See [CHANGELOG.md](CHANGELOG.md#unreleased) |
| 61 | Mainnet archive integration test suite — read-only RPC sweep [D:3/B:6/U:7 → Eff:2.17] 🚀 | ✅ | Done 2026-04-30. `test/rpc_integration_test.exs` (20 tests, `async: true`, `@moduletag :integration`) + `Cartouche.Test.Live` helper at `test/support/live.ex`. Per-call `client: Finch` + `ethereum_node` opts (CCXT-style local-object pattern, no `Application.put_env`). Opt-in via `mix integration` or `mix test --include integration`. `mix.exs` adds `integration: ["test --only integration"]` alias and `integration: :test` in `cli/0`'s `preferred_envs`. `test_helper.exs` excludes `:integration` from default. **Surfaced two real Task-60-class bugs the mock client masked** — `get_block_by_hash/2` was missing the required `fullTransactionObjects` second wire param (`-32602 Invalid params` from real nodes), and `to_call_params/2` for V1 encoded `data` via `Hex.encode_short_hex/1` producing invalid `"0x0"` for empty calldata. Both fixed in this release; see CHANGELOG `[Unreleased]`. Decoder gaps tracked as Tasks 62–68 below. Default URL `http://127.0.0.1:8545` (blockwatch-one tunnel); override via `CARTOUCHE_LIVE_NODE_URL`. Trace methods deferred to Task 62 |
| 62 | v2 traces — integration anchors for `trace_transaction`, `trace_call`, `trace_callMany`, `debug_traceCall` [D:5/B:5/U:5 → Eff:1.0] 📋 | ⬜ | Extend `test/rpc_integration_test.exs` with the four trace methods deferred from Task 61's v1 scope. Anchor selection caveat: node-implementation variance — geth/reth/erigon differ on internal trace fields, so picking mainnet anchor txs that produce stable shape across implementations is non-trivial. The current opcode whitelist covers all post-Pectra mainnet `debug_traceCall` opcodes (verified 2026-05-01 against go-ethereum `core/vm/opcodes.go` — Codex consultation under Task 68 closure); pick anchors freely, including 7702 delegation txs. The forward-compat gap is CLZ at Osaka activation, tracked as Task 70. Pre-implementation: probe the live archive node for a known-stable historical tx and confirm trace shape against the existing `Cartouche.Trace.deserialize/1` and `Cartouche.DebugTrace.StructLog.deserialize/1` decoders. Coverage gate: `Cartouche.Trace` is at 100%, `Cartouche.TraceCall` likely OK; `Cartouche.DebugTrace.StructLog` needs check |
| 63 | `Cartouche.Block` — add `base_fee_per_gas` (London+) [D:1/B:3/U:5 → Eff:4.0] 🎯 | ✅ | Done 2026-04-30 (Block decoder bundle 63+64+65). `base_fee_per_gas` field decoded from `params["baseFeePerGas"]` via `Hex.decode_hex_number!/1`; pre-London blocks deserialize with `nil`. Integration test at `test/rpc_integration_test.exs` strengthens from `refute Map.has_key?` → `assert b.base_fee_per_gas > 0` against the post-London 15M anchor |
| 64 | `Cartouche.Block` — add `withdrawals_root` and `withdrawals` (Shanghai+) [D:2/B:3/U:5 → Eff:2.0] 🚀 | ✅ | Done 2026-04-30 (Block decoder bundle 63+64+65). New nested `Cartouche.Block.Withdrawal` submodule (matches `Cartouche.Receipt.Log` precedent) with `index/validator_index/address/amount` fields and own `deserialize/1` + doctest. `Block.deserialize/1` decodes `withdrawalsRoot` (32-byte hash) and `withdrawals` (list of `%Withdrawal{}` via per-element `Withdrawal.deserialize/1`). Integration test at the post-Shanghai 18M anchor pins shape via `assert [%Cartouche.Block.Withdrawal{} \| _] = b.withdrawals` |
| 65 | `Cartouche.Block` — add Cancun fields (`parent_beacon_block_root`, `blob_gas_used`, `excess_blob_gas`, `mix_hash`) [D:2/B:3/U:5 → Eff:2.0] 🚀 | ✅ | Done 2026-04-30 (Block decoder bundle 63+64+65). All four fields decoded; `parent_beacon_block_root` via `decode_word!/1`, blob fields via `decode_hex_number!/1`. `mix_hash` decodes whenever present (pre-Merge PoW mix hash; post-Merge PREVRANDAO per EIP-4399). Integration test at the post-Cancun 20M anchor asserts `byte_size(b.parent_beacon_block_root) == 32`, `is_integer(b.blob_gas_used)`, `is_integer(b.excess_blob_gas)`, `byte_size(b.mix_hash) == 32` |
| 66 | `Cartouche.Block.transactions` — implement `include_transaction_details: true` `[CSR]` (split candidate: decoder is `[CX]`) [D:5/B:4/U:5 → Eff:0.9] ⚠️ | ⬜ | `Cartouche.RPC.get_block_by_number/2` and `get_block_by_hash/2` accept the `:include_transaction_details` opt and forward `true`/`false` to the node, but `Cartouche.Block.deserialize/1` currently hardcodes `transactions: []` regardless of what the node returned. When `true`, the node returns full transaction objects (V1 or V2 shape depending on tx type) instead of just hashes. Implement: dispatch on the shape of each `params["transactions"]` element (string → tx hash, map → full V1/V2 object). Reuse existing `Cartouche.Transaction.V1.decode/1` / `V2.decode/1` if shapes line up, or write a JSON-shape decoder. Add an integration anchor for the `true` shape. Pre-mutation gate: `Cartouche.Block` coverage check; this is a contract-narrowing on existing public API. **U bumped 4→5 (2026-04-30):** `:include_transaction_details` is now an explicitly-documented public option on both `get_block_by_*` `@doc`s — every user who tries `true` hits `transactions: []` and has to read the caveat |
| 67 | `Cartouche.Receipt` — add EIP-4844 blob fields (`blob_gas_used`, `blob_gas_price`) [D:2/B:3/U:4 → Eff:1.75] 🚀 | ✅ | Done under `[Unreleased]`. `Cartouche.Receipt` now carries nil-tolerant EIP-4844 blob gas fields, decoded from `blobGasUsed` / `blobGasPrice` when present. Unit coverage pins populated, zero, and absent shapes; integration coverage adds a type-3 mainnet blob receipt anchor at block 19,449,343 and strengthens the type-2 anchor to assert nil blob fields |
| 68 | ~~`Cartouche.DebugTrace.StructLog` — add EIP-7702 opcodes to the closed whitelist (`AUTH`, `AUTHCALL`)~~ — **closed obsolete (premise corrected)** | ✅ | Closed 2026-05-01 — the task's two technical premises were both wrong, verified against the EIP-7702 spec, ethereum.org/roadmap/pectra, and go-ethereum master `core/vm/opcodes.go` (independently corroborated by Codex consultation pulling geth master + v1.14.12 + EIP-3074 spec). (1) `AUTH` (0xf6) and `AUTHCALL` (0xf7) were EIP-3074 opcodes — EIP-3074 displays a 🛑 Withdrawn badge and never reached any client. EIP-7702 was authored as 3074's *replacement*, swapping the new-opcode design for delegation indicators (`0xef0100 \|\| address`) that modify behaviour of existing `CALL`/`CALLCODE`/`DELEGATECALL`/`STATICCALL` — geth's `enable7702` in `core/vm/eips.go:571–575` adjusts gas only, no opcode slots. (2) Pectra activated 2025-05-07 at epoch 364032 — 12 months ago — bundling 10 EIPs that ship zero new opcode mnemonics. The current closed whitelist (`lib/cartouche/debug_trace.ex:56–67`) covers all live mainnet opcodes; 7702 delegation txs decode cleanly because the on-the-wire `op` strings remain standard CALL-family. The forward-compat gap is `CLZ` (0x1e, EIP-7939) which lands in geth's `newOsakaInstructionSet()` for the upcoming Fusaka fork — filed separately as Task 70 with a real activation gate. Replaces this task entirely |
| 69 | Audit RPC-level requirements bubbling up from defi-skills mining [D:2/B:5/U:4 → Eff:2.25] 🎯 | ⬜ | **Depends on the four sibling-repo `defi-skills:intent-to-transaction` mining tasks completing first** (planted in `hieroglyph`, `onchain`, `onchain_aave`, `onchain_evm` ROADMAPs on 2026-04-30). After those tasks publish their "Proposed additions from defi-skills mining" sections, scan them for any RPC-level requirements that bubble down to cartouche — e.g. `eth_call` edge cases (revert-data shape, gas-stipend behavior), `eth_estimateGas` semantics on reverts, log-filter quirks, fee-history math, `eth_getCode` for proxy detection. Add any surfaced needs as new Phase 0.5 / Phase 2 tasks here. If nothing surfaces after all four upstream tasks close, mark this complete as "no action needed." Read-only triage exercise — no cartouche code edits in this task itself |
| 70 | `Cartouche.DebugTrace.StructLog` — add `CLZ` (EIP-7939/Osaka) to the closed whitelist `[CX]` [D:1/B:2/U:3 → Eff:2.5] 🎯 | 🔶 | **Blocked on Fusaka/Osaka mainnet activation** (no firm date as of 2026-05-01). `CLZ` ("count leading zeros") is in go-ethereum master's `newOsakaInstructionSet()` per [EIP-7607](https://eips.ethereum.org/EIPS/eip-7607) Osaka composition, with [EIP-7939](https://eips.ethereum.org/EIPS/eip-7939) defining the opcode at slot `0x1e`. Once Osaka activates, any `eth_debug_traceCall` against an Osaka tx that uses CLZ will raise `ArgumentError` in the closed whitelist. Pre-add gate: confirm the mnemonic emitted in struct-logs matches `"CLZ"` exactly against an Osaka testnet trace (geth's `opCodeToString` in `core/vm/opcodes.go` master is the source of truth); add the atom to `@single_opcodes` in `lib/cartouche/debug_trace.ex` and a regression test that round-trips the new mnemonic. Watch list for Amsterdam (post-Osaka): SLOTNUM (0x4b, EIP-7843) — currently Draft, file separately when EIP leaves Draft and Amsterdam composition firms up. Replaces the abandoned Task 68 (which conflated EIP-3074's withdrawn AUTH/AUTHCALL with EIP-7702). Discovered during Codex consultation 2026-05-01 |
| 73 | ~~KMS signer Goth-path test mocking — clear critical-tier ≥95% gate on both KMS signers~~ [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ✅ | Done 2026-05-04. Added `:meck` 1.1.x test infrastructure for `Goth.fetch!/1` and credential-path `get_address/6` + `sign/7` coverage on both Ethereum and Solana KMS signers. The 2-arg `client(cred)` branch now drops out of both modules' uncovered line lists; see [CHANGELOG.md](CHANGELOG.md#unreleased) |
| 75 | Backfill `@spec` on every `defp` to enable `.credo.exs` `{Specs, [include_defp: true]}` portfolio-wide `[CX]` (per-file batches; final `.credo.exs` flip is local) [D:7/B:5/U:5 → Eff:0.71] ⚠️ | ⬜ | The `~/.claude/includes/development-philosophy.md` "Marking Internal API Surface" mandate says every function (`def` AND `defp`) gets `@spec`. Enabling `{Credo.Check.Readability.Specs, [include_defp: true]}` in `.credo.exs` today triggers **3797 missing-`@spec` violations** across `lib/` and `test/` (verified via `mix credo --strict --format json`, 2026-05-04). The change was attempted as part of the 2026-05-04 generator-pass commit and stashed (`git stash push -m "WIP: .credo.exs Specs include_defp:true (deferred to Task 75 backfill)"`) so the generator change could ship without CI regression — the staged `.credo.exs` flip plus the working-tree edit both reverted; the stash entry preserves the user's intent for re-stage. Backfill shape: walk `lib/cartouche/**/*.ex` and `test/support/**/*.ex`, add `@spec` to every `defp` that lacks one — placeholder `term()` specs are acceptable on hot-path data plumbing where domain types are unclear, with a `TODO:` marker explaining the gap. Acceptance: `mix credo --strict` passes with `Specs include_defp:true` enabled in `.credo.exs`; the stashed `.credo.exs` change re-applies cleanly via `git stash apply` (or hand-restored from the WIP stash) and stages without re-introducing violations. Likely tractable as a Codex-delegated cluster (per-file batches), but the `.credo.exs` flip itself must land in the same commit as the final batch to keep CI green throughout the rollout. Discovered 2026-05-04 during the staged review of the generator `@doc/@spec` annotation pass |
| 76 | Restore dialyzer to CI — separate workflow on a larger runner [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Dialyzer was removed from the PR harness 2026-05-04 (see CHANGELOG `[Unreleased] ### Tooling`) because the deps PLT exceeds the 16 GB `ubuntu-latest` budget — even after `:plt_ignore_apps` trimmed the GCP cluster, run 25319850405 OOM'd at 12:52:25 while adding 621 modules to the deps PLT. Local `mix dialyzer.json` works fine against a warm `priv/plts/` cache. **Upstream investigation 2026-05-04** ruled out dep-side slimming as a path: `googleapis/elixir-google-api` ships zero dialyzer config in its own CI (`.github/workflows/presubmit.yml` runs only `mix do deps.get, test` per changed client) — package authors don't dialyze the GCP cluster either; 600+ generated REST modules per client makes dialyzer prohibitively expensive at the source. Sibling deps (`google_gax`, `goth`, `jose`) ship no `:plt_optional` flag or dialyzer hints to consumers. `:plt_ignore_apps` IS the canonical pattern there — no further upstream lever exists. **Restoration shape** (pick one when justified): (a) **separate workflow** `.github/workflows/dialyzer.yml` triggered only on push-to-`development` (not PR) using `runs-on: ubuntu-latest-large` (32 GB) — keeps PR CI fast/cheap, dialyzer signal arrives at merge time; (b) **trim more aggressively** by adding `:hieroglyph`, `:descripex`, `:finch`, `:mint`, `:hpax`, `:inets`, `:xmerl` to `:plt_ignore_apps` and broaden `.dialyzer_ignore.exs` to suppress the resulting `unknown_function` cascade — reduces dialyzer's value materially since it can no longer cross-check cartouche's hieroglyph/descripex usage; (c) **scheduled nightly** via `cron` on the same larger runner — slowest feedback loop but lowest cost. Don't pursue until one of these triggers fires: external contributor PRs (need pre-merge signal), a critical-tier refactor that benefits from dialyzer-in-CI evidence, or a generator regression class that local-only dialyzer missed. Task 50 closure does NOT change the calculus — Task 50 affects the cartouche app PLT (tightening `@spec`s on generated bindings to replace `term()` with ABI-derived types), not the deps PLT where the OOM happens. Discovered 2026-05-04 during INE-10 / PR #8 CI iteration — bundling fix attempts (`:plt_ignore_apps` trim → swap step → revert) demonstrated the structural budget gap |
| 74 | ~~`Cartouche.Wei.to_wei/1` — add `:eth` denomination with `Decimal` support~~ [D:3/B:3/U:3 → Eff:1.0] 📋 | ✅ | Done 2026-05-04 (PR #14). See [CHANGELOG.md](CHANGELOG.md#unreleased). |

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
| 39 | ~~RecoveryBit doctest chain-id portability cleanup~~ `[CX]` [D:2/B:1/U:1 → Eff:0.5] ⚠️ | ✅ | Done 2026-05-04 (PR #4 / INE-7). Chain-id-dependent doctests rewritten as chain-agnostic; EIP-155 behaviour moved to focused ExUnit assertions in `test/recovery_bit_test.exs`. See [CHANGELOG.md](CHANGELOG.md#unreleased). |

### 1.2 `Cartouche.Wei.to_wei/1` — narrow `integer()` → `non_neg_integer()` ✅

Spec narrowed input + return both to `non_neg_integer()` with matching `amount >= 0` guards (2026-04-29). Wei is a discrete count by domain; all internal callers already pass non-negative values.

### 1.3 `Cartouche.Signer.sign_direct/4` — `mfa()` → `{module(), atom(), list()}` ✅

Dialyzer reported `signer.ex:141 invalid_contract`. 3rd arg specced as `mfa()` (Elixir defines as `{module(), atom(), arity :: non_neg_integer()}`) but the impl receives `{module(), atom(), args :: list()}`. Fixed 2026-04-26 along with the same regression about to ship via `start_link/1`.

### 1.1–1.3 bundled task ✅

Phase 1.1 landed 2026-04-25 (Task 38). Phase 1.3 landed 2026-04-26 (typespec sweep — see CHANGELOG `[Unreleased]`). Phase 1.2 landed 2026-04-29 (`Cartouche.Wei.to_wei/1` narrowed). All three closed.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 7+8+9 | Phase 1.1–1.3 surgical spec fixes [D:1/B:3/U:6 → Eff:4.5] 🎯 | ✅ | Done 2026-04-29. Phase 1.1 ✅ landed under Task 38 (`Cartouche.RecoveryBit` promotion). Phase 1.3 ✅ landed 2026-04-26 — `mfa()` BIF replaced with `{module(), atom(), [any()]}` on both `Cartouche.Signer.sign_direct/4` and `Cartouche.Signer.start_link/1`. Phase 1.2 closeout 2026-04-29 — `Cartouche.Wei.to_wei/1` spec narrowed `integer() | {integer(), :wei | :gwei}) :: integer()` → `non_neg_integer() | {non_neg_integer(), :wei | :gwei}) :: non_neg_integer()`, with `amount >= 0` guards on all three clauses. Wei is a discrete count by domain — every internal caller (`Cartouche.Transaction` constructors, `Cartouche.RPC` fee-suggestion fallbacks) already passes non-negative values; the spec was simply loose. Negative inputs now raise `FunctionClauseError` at the boundary. New `describe "spec boundaries (Phase 1.2)"` block in `test/wei_test.exs` covers the zero boundary on all three clauses, the large-value identity round-trip, the `:gwei` multiplier, and the negative-input rejection — grounded as ExUnit assertions per `feedback_doctests_not_substitute_for_tests.md`. `Cartouche.Wei` coverage stays at 100%; full suite green (778/778); dialyzer clean on `wei.ex`. Closes Phase 1; downstream onchain `@dialyzer {:no_match}` strip on `Onchain.Hex` / ABI / ERC / ENS / Multicall callers becomes load-bearing once cartouche `0.1.x` ships (Task 6) |

### 1.4 `Cartouche.Hex` return-type specs

**Root cause:** private `Cartouche.Hex.decode_hex_/1` (`lib/cartouche/hex.ex:374`) returns `{:ok, t()} | :invalid_hex` but is specced `{:ok, t()} | :error`. All public callers inherit this:

| Function | Line | Current `@spec` | Actual return |
|----------|------|-----------------|---------------|
| `decode_hex/1` | 80 | `{:ok, t()} \| :error` | `{:ok, t()} \| :invalid_hex` |
| `decode_hex_number/1` | 245 | `{:ok, integer()} \| :error` | `{:ok, integer()} \| :invalid_hex` |
| `from_hex/1` | 91 | `t() -> String.t()` | `t() -> {:ok, t()} \| :invalid_hex` (alias for `decode_hex`) |
| `from_hex!/1` | 102 | `t() -> String.t()` | `t() -> t()` (alias for `decode_hex!`) |

Doctests and `@doc` examples already show the correct shape; only the `@spec` lines disagree. Fix is surgical — update the four specs, no implementation change.

**Closeout (2026-04-28):** the four `@spec` lines plus the private `decode_hex_/1` were corrected as a drive-by in commit `8d4bc18` ("doctor, credo fixes", 2026-04-26) — `:error` → `:invalid_hex` on `decode_hex/1`, `decode_hex_number/1`, `decode_hex_/1`, and `from_hex/1`; `t() -> String.t()` → `t() -> t()` on `from_hex!/1`. Dialyzer has been clean on `hex.ex` since (verified post-`8d4bc18` and again 2026-04-28: 0 warnings filtered to the file, total `invalid_contract` count 8 — `hex.ex:93` no longer in the list). The 2026-04-28 closeout commit grounds the corrected specs with focused ExUnit assertions (`test/hex_test.exs` `describe "spec boundaries (Phase 1.4)"`) per the project memory `feedback_doctests_not_substitute_for_tests.md`, adds the missing failure-path doctests to `from_hex/1` and `from_hex!/1` (parity with `decode_hex/1` / `decode_hex!/1`), and bundles a small `deep_encode_binaries/1` coverage block (4 lines) that lifts `Cartouche.Hex` from 94.29% to 100% — clearing the ≥95% critical-tier gate prophylactically.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 10+11+12+13 | Phase 1.4 Hex spec audit + `from_hex/1` fix + doctest coverage [D:2/B:7/U:9 → Eff:4.0] 🎯 | ✅ | Done 2026-04-28. Spec corrections shipped under commit `8d4bc18` (drive-by during the doctor/credo cleanup, 2026-04-26) — five specs corrected, `:error` → `:invalid_hex` on the four public callers and the private helper; `t() -> String.t()` → `t() -> t()` on `from_hex!/1`. Closeout commit 2026-04-28 grounds the corrections with (a) the missing `:invalid_hex` doctest on `from_hex/1`, (b) the missing raise-path doctest on `from_hex!/1`, (c) ExUnit `describe "spec boundaries (Phase 1.4)"` in `test/hex_test.exs` pinning the four return shapes per `feedback_doctests_not_substitute_for_tests.md`, and (d) a small `deep_encode_binaries/1` coverage push raising `Cartouche.Hex` 94.29% → 100% (critical-tier gate cleared). Dialyzer outcome: 0 `hex.ex` warnings, total `invalid_contract` count 8 (down from the 11 audited pre-Phase-0.4). Onchain `@dialyzer {:no_match}` strip on `Onchain.Hex` and the cascading ABI / ERC / ENS / Multicall callers becomes load-bearing once this ships in `0.1.x` (Task 6) |

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
| 14+15+35 | Phase 2 RPC error-shape widening `[CSR]` [D:4/B:7/U:7 → Eff:1.75] 🚀 | 🔄 in-flight (INE-25) | **Step 1 (Task 14):** re-audit `send_rpc/3` `@spec` vs runtime shapes on the ported code — confirm the table above; some shapes may have been tightened in intervening signet commits before the fork. **Step 2 (Task 15):** widen or tag-split the error type with doctest coverage per shape. Keep `%{code, message}` as the JSON-RPC-error branch; union in the others. **Step 3 (Task 35):** rescue `Jason.EncodeError` / `Protocol.UndefinedError` at `Jason.encode!(body)` in **both** `lib/cartouche/rpc.ex:162` (Ethereum) and `lib/cartouche/solana/rpc.ex:68` (Solana) → `{:error, {:invalid_params, _}}`, so non-JSON-encodable inputs honor the `{:ok,_}\|{:error,_}` contract on both transports instead of raising. Triggers (apply to both): `<<255>>` method binary (non-UTF-8 passes `is_binary/1` but Jason raises); params containing tuples / atom-keyed maps. Doctests per trigger in each RPC module. The new `{:invalid_params, _}` joins the union from Step 2. Discovered 2026-04-24 during onchain Task 59 (`Onchain.RPC.call/3` — generic JSON-RPC passthrough; Ethereum side); Solana side surfaced 2026-04-26 during Codex consultation. Once this lands, all `Onchain.RPC.*` wrappers automatically honor their `@spec` and the same guarantee extends to Solana RPC consumers |

**Blast radius** (from `mix reach.impact Cartouche.RPC.send_rpc/3`, pre-rename): 6 direct callers break on signature change (`get_balance/2`, `get_transaction_count/2`, `eth_block_number/1`, `eth_chain_id/1`, `set_filter/1`, `Cartouche.Filter.handle_info/2`), 1 transitive (`Cartouche.Signer.init/1`), no return-value dependents. Behavior-preserving spec-widening is low-risk; a union-type split needs all 6 direct callers to still type-check.

---

## Phase 3: `Cartouche.Trace` + `Cartouche.TraceCall` deserialize specs ✅

**Why:** Dialyzer reports `trace.ex:408` and `trace_call.ex:124` as `invalid_contract`. The struct returned by `deserialize/1` has fields with union types (`nil | binary()`, `nil | <<_:160>>`, etc.) that the module's `@type t` declaration doesn't allow.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 16+17+18 | ~~Phase 3 Trace + TraceCall deserialize specs + tests~~ `[CX]` [D:3/B:2/U:4 → Eff:1.0] 📋 | ✅ | Done 2026-05-04 (PR #17 / INE-14). `Cartouche.Trace.@type t` (incl. nested `Action`) and `Cartouche.TraceCall.@type t` widened to admit `nil` on optional fields; action serialization now nil-safe. Grounding ExUnit assertions land in `test/trace_test.exs` and `test/trace_call_test.exs`. Dialyzer drops `trace.ex:408` and `trace_call.ex:124` `invalid_contract`. See [CHANGELOG.md](CHANGELOG.md#unreleased). |

---

## Phase 4: `Cartouche.Typed` internal-function specs

**Why:** Dialyzer reports `typed.ex:571` (`encode_value_map/3`) and `typed.ex:585` (`find_type/2`) as `invalid_contract`. Both specs completely disagree with the success typing — looks like copy-paste from a sibling function or a stale spec after a refactor.

- `encode_value_map/3`: spec returns a map; impl returns a `bitstring()`.
- `find_type/2`: spec returns `Typed.Type.t()`; impl returns a 2-tuple.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 19+20 | Phase 4 Typed internal-function specs — rewrite + visibility judgment `[CX]` [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | **Blocked on Task 45.** Read current impls, derive the true return types, rewrite both `@spec` lines (Task 19). If these really are internal, add `@doc false` — keeps the `@spec` for dialyzer but removes from generated docs. Then decide whether either fn is meant to be public API (Task 20); if so, adjust impl to match the documented intent instead of changing the spec. Judgment call; easier under fork ownership since we decide |
| 45 | `Cartouche.Typed` coverage push — exercise `encode_value_map/3` and `find_type/2` with representative inputs before rewriting their specs `[CSR]` [D:2/B:2/U:3 → Eff:1.25] 📋 | 🔄 in-flight (INE-21) | 📦 **Typed cleanup bundle entrypoint** — chain into 19+20 spec rewrite in the same session; the coverage tests *are* the spec-rewrite evidence. Currently 94.44% (`mix test.json --cover` 2026-04-26). Gate for Tasks 19 + 20. The two specs being rewritten disagree with success typing; the rewrite needs tests of the actual return shapes (map vs bitstring for `encode_value_map/3`; `Typed.Type.t()` vs 2-tuple for `find_type/2`) so the new specs are grounded in observed behavior, not re-derived from reading the impl. Acceptance: both functions have ≥1 test exercising each return-shape branch |

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
| 21+22 | Phase 5 `none()` cascade investigation + targeted fix or local suppression `[CSR]` [D:5/B:4/U:5 → Eff:0.9] ⚠️ | ⬜ | **Blocked on Task 46.** Trace each Phase 5 warning back through `mix reach.deps` + `mix reach.slice` to find the first callee with `none()` success typing (Task 21, half-day to day). If root cause is a genuinely fixable spec narrowing, fix it; if it's structural (`raise`-heavy helpers), add `@dialyzer {:no_contracts, …}` locally in cartouche (Task 22). Local suppression is a valid terminal state |

---

## Phase 6: `Cartouche.VM.Context.init_from/2` spec

**Why:** `vm.ex:104 invalid_contract`. Spec says `:: t()` but success typing is the concrete struct literal, suggesting `@type t` is too loose or missing. Low-impact standalone.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 23 | Align `Cartouche.VM.Context.@type t` with dialyzer's inferred struct shape, or relax `init_from/2` to return `struct()` `[CX]` [D:2/B:1/U:3 → Eff:1.0] 📋 | ⬜ | **Blocked on Task 46.** Internal type. Bundle with Phase 5 if that opens a VM file anyway |
| 46 | VM + Erc20.Call coverage push — gate Phases 5 and 6 `[CSR]` [D:4/B:5/U:5 → Eff:1.25] 📋 | 🔄 in-flight (INE-22) | 📦 **VM dialyzer cleanup bundle entrypoint** — chain into 21+22 (`none()` cascade) + 23 (`VM.Context.@type t`) in the same session, single VM mental model. Three modules below the bar (`mix test.json --cover` 2026-04-26): `Cartouche.VM.Context` 35.71% (Phase 6 target — 9 uncovered), `Cartouche.Erc20.Call` 0% (Phase 5 target — 6 uncovered), `Cartouche.VM.InvalidVm` 0% (1 uncovered, exception module — at minimum a `raise/rescue` round-trip; renamed from `VmError` in the credo cleanup pass). Cover `VM.Context.init_from/2` happy + edge inputs (the function whose spec Phase 6 narrows); cover `Erc20.Call` entry points used by the `none()`-cascade investigation in Phase 5. Acceptance: all three modules ≥ 80% on `mix test.json --cover` |

---

## Phase 7: Dependency freshness

Single-repo ownership simplifies this — we edit `mix.exs` and `mix.lock` directly, no dual-branch dance.

### 7.1 `google_api_cloud_kms` 0.38.1 → 0.43.0

`mix.exs` previously pinned `~> 0.38.1` (resolved `< 0.39`); now `~> 0.43.0` post-Tasks-24+25. Cartouche uses this in **two** signer modules — `lib/cartouche/signer/cloud_kms.ex` (Ethereum, secp256k1 `digest.sha256` sign) and `lib/cartouche/solana/signer/cloud_kms.ex` (Solana, `EC_SIGN_ED25519` raw-message sign) — both via `cloudkms_..._get_public_key` and `cloudkms_..._asymmetric_sign`, which collapsed at 0.40.0 from arity 6/7 (split path components) to arity 4 (`(connection, name, optional_params \\ [], opts \\ [])` with a single `name` resource path). Both modules are wrapped in `if Code.ensure_loaded?(GoogleApi.CloudKMS.V1.Api.Projects)` and gated as critical-tier (≥95% coverage gate per `critical-rules.md`) — current coverage 88% / 90% post-bump; Goth-path mocking (Task 73) is the deferred follow-up to clear the gate.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 24+25 | Phase 7.1 `google_api_cloud_kms` 0.38.1 → 0.43.0 [D:3/B:3/U:4 → Eff:1.17] 📋 | ✅ 2026-05-02 | Audit (hex tarball diff): breaking change at 0.40.0 — `get_public_key` / `asymmetric_sign` collapsed to arity 4 (single `name` resource path). Both KMS signer modules updated to construct `name` internally via `defp key_version_name/5`; public API of `Cartouche.{Signer,Solana.Signer}.CloudKMS` preserved. PublicKey / AsymmetricSignResponse / Connection / Goth path unchanged across 5 minors. Pre-mutation coverage push: Eth 69→88%, Solana 69→90% (algorithm-mismatch + malformed-DER ExUnit assertions). See CHANGELOG `[0.1.3]` for full audit trail |
| 26 | Conditional feature-surface pass — expose HMAC / attestation / new auth methods if Task 24 flagged anything relevant (Ed25519 already ships via the Solana signer — that branch of the original framing is closed) [D:5/B:4/U:4 → Eff:0.8] ⚠️ | ✅ 2026-05-02 | Closed as superseded — `EC_SIGN_ED25519` already shipped via `Cartouche.Solana.Signer.CloudKMS` in earlier work; no HMAC / attestation / new auth surfaces in 0.39 → 0.43 worth promoting to Cartouche-level helpers per the 24+25 audit |

### 7.2 `ex_doc` 0.31.1 → 0.40

`mix.exs` already carries `~> 0.40` (kept from the `:reach` requirement — `reach` pulls `makeup_elixir ~> 1.0` which conflicted with upstream's `ex_doc 0.31.1 → ~> 0.14`). No additional action needed beyond Task 4 verifying `mix docs` produces clean output.

### 7.3 `finch` 0.19 → 0.21

`mix.exs` pins `~> 0.19`. Cartouche uses Finch in `lib/cartouche/rpc.ex:167` and the error-normalizer in `util.ex:481`. Two minors of HTTP/2 and pool improvements — may simplify how we hand-build error strings from `%Finch.Error{}`.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 27+28 | Phase 7.3 `finch` 0.19 → 0.21 — audit + conditional adoption [D:2/B:3/U:4 → Eff:1.75] 🚀 | ⬜ | Read CHANGELOG 0.19 → 0.21; identify options relevant to `Finch.request/3` or error classification (Task 27). If concrete wins surface (cleaner error variants, better pool config, HTTP/2 telemetry), adopt with tests (Task 28) |

### 7.4 Lockfile refresh

`ex_sha3`, `goth`: constraints already permit newer versions; `mix deps.update` and verify. `junit_formatter` and `bandit` need a small pin/lockfile dance — commit `860ac52` ("Tighten dep pins to match refreshed lockfile") rewrote `~> 3.3` to `~> 3.3.1`, which now blocks 3.4.0; `bandit` was never in roadmap. Tracked as Tasks 71 + 72 below. Bundle the lot into a single dep PR.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 71 | `junit_formatter` 3.3.1 → 3.4.0 — loosen pin + lock refresh [D:1/B:1/U:1 → Eff:1.0] 📋 | ✅ 2026-05-02 | Pin loosened `~> 3.3.1` → `~> 3.3`; `mix deps.update` resolved 3.4.0; full suite green |
| 72 | `bandit` 1.10.4 → 1.11.0 — lock refresh [D:1/B:1/U:1 → Eff:1.0] 📋 | ✅ 2026-05-02 | Lock-only refresh — pin `~> 1.10` already permitted 1.11.0; `mix deps.update bandit` resolved. Actual 1.11.0 boot deferred to next user-Tidewave-restart (the running session keeps 1.10.4 beam loaded); lock + dialyzer + test suite verified clean |

---

## Phase 8: `Cartouche.Transaction.V2.encode/1` duplication

**Why:** `mix ex_dna` surfaces one Type I (exact) clone in `lib/cartouche/transaction.ex`: both `encode/1` clauses of `Cartouche.Transaction.V2` (unsigned at line 394, signed at line 423) share 10 lines of identical struct destructuring and the same `<<0x02>> <> ExRLP.encode([...])` prefix. The signed clause differs only by appending the normalized `signature_y_parity` / `signature_r` / `signature_s` triple and applying `Enum.map/2` to the access list.

Natural extraction: a private helper returning the prefix list from the struct. Each clause either encodes that list as-is (unsigned) or concatenates the signature triple before encoding (signed).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 29+30 | Phase 8 V2 encode dedup — verify doctest coverage + extract helper `[CX]` [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Verify both encode clauses have doctest coverage; add one to the unsigned clause if missing (Task 29) — refactors without test coverage are risky. Then extract `defp unsigned_rlp_list/1`; rewrite both clauses to call it; verify byte-exact output equivalence via doctests (Task 30) |

**Do not run `mix ex_dna --literal-mode abstract` for refactor targets.** It finds near-misses that are often intentional (EIP version pairs, opcode groupings). Type I / exact duplication only.

---

## Phase 9: New transaction types + raw decode

**Why:** The three features that genuinely require cartouche internals. Under fork ownership these ship when ready — no review-cadence gating.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 31 | EIP-4844 blob transactions (`Cartouche.Transaction.V3`) — encode, sign, RLP round-trip, `max_fee_per_blob_gas` + `blob_versioned_hashes` fields `[CSR]` [D:6/B:7/U:7 → Eff:1.17] 📋 | 🔄 in-flight (INE-23) | L2 rollups have posted blob txs since Dencun (Mar 2024). Include doctest + representative test vector from mainnet |
| 32 | EIP-7702 authorization-list transactions (`Cartouche.Transaction.V4`) — `authorization_list` field, tx type 0x04 `[CSR]` [D:5/B:5/U:6 → Eff:1.1] 📋 | ✅ | Done 2026-05-05. `Cartouche.Transaction.V4` supports EIP-7702 encode/decode/sign/hash for set-code transactions, including authorization tuple signing/recovery via the `0x05 || rlp([chain_id, address, nonce])` digest. Unit coverage pins round-trips, empty and multi-entry authorization lists, malformed input rejection, outer signature recovery, and authorization authority recovery. Mainnet vector coverage decodes a real post-Pectra type-4 transaction and verifies the raw tx hash plus outer and authorization signatures. |
| 33 | Raw transaction decode — inverse of `Cartouche.Transaction.Vn.encode/1` across V1/V2/V3/V4 `[CSR]` [D:4/B:4/U:6 → Eff:1.25] 📋 | ⬜ | Useful for mempool tooling, explorers. The existing surface feels incomplete without it |

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

## Phase 11: hieroglyph 1.0.0 → 1.4.0 adoption advisory

**Status:** 🔄 partially complete — decode-struct atom audit fixed under INE-17; bug-fix audit and optional API-adoption triage remain pending.

**Context.** `hieroglyph` shipped four minor releases between 2026-04-24 and 2026-05-01: 1.0.0, 1.1.0, 1.2.0, 1.3.0, 1.4.0. The `{:hieroglyph, "~> 1.0"}` pin in `mix.exs` already accepts 1.4.0 — next `mix deps.update hieroglyph` pulls it. Full release notes in `../hieroglyph/CHANGELOG.md`; sibling roadmap at `../hieroglyph/ROADMAP.md` (now in maintenance posture). One change is BREAKING-on-opt-in-path; several silent bug fixes affect cartouche's existing decoded data; three new APIs are worth optional adoption.

### Tasks

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| TBD | Audit two `decode_structs: true` paths against 1.4.0 atom-existence requirement `[CSR]` | ✅ | 5 | 7 | 5 | 1.20 📋 | `Cartouche.gen` + `Cartouche.Sleuth` |
| TBD | Bug-fix audit: re-test cartouche flows against silently-fixed hieroglyph behaviors `[CSR]` | ⬜ | 2 | 5 | 3 | 2.00 🚀 | `Cartouche.Filter` + ABI flows |
| TBD | Optional: adopt new hieroglyph public APIs where they simplify cartouche `[CX]` | ⬜ | 2 | 3 | 2 | 1.25 📋 | `Cartouche.gen` + `Cartouche.RPC` |

### Audit 1 — `decode_structs: true` and atom existence

Hieroglyph 1.4.0 hardened the `decode_structs: true` path: field-name atoms must already exist in the VM atom table (`String.to_existing_atom/1` instead of `String.to_atom/1`). Decoder raises `ArgumentError` with a migration hint otherwise. Closes a DoS surface (atom-table exhaustion via attacker-controlled ABI field names); behavior change on the opt-in path. Two cartouche call sites:

- `lib/mix/cartouche.gen.ex:607-610` — 🔧 fixed. The generator's `*_selector/0` template returns `Macro.escape(selector)` metadata whose return-field names remain strings (`%{name: "blockNumber"}` / `%{name: "cool"}`), not compile-time atom literals. Generated `exec_vm_*` wrappers now call a private `preintern_return_atoms!/1` helper before `ABI.decode(..., decode_structs: true)`, recursively covering tuple and array return types. Regenerated test-support bindings prove the emitted shape.
- `lib/cartouche/sleuth.ex:91-128` — 🔧 fixed. `query_v2/4` accepts runtime selectors and defaults `decode_structs: true`, so callers can supply selectors whose field atoms are not yet interned. `try_decode/3` now pre-interns the bounded selector return-field atoms before decode. Regression coverage uses `Code.loaded?/1` and a dynamically unique field name to prove raw Hieroglyph decode raises while the Cartouche boundary succeeds.

### Audit 2 — silent bug-fix windfall (1.0.0–1.2.0)

Cartouche flows may have been miscompiling/decoding without symptoms. Re-test:

- **Indexed reference-type event params** (1.0.0) — `lib/cartouche/filter.ex:114` calls `ABI.Event.decode_event/4`. Events with indexed `string` / `bytes` / `T[]` (fixed or dynamic) / tuple params previously returned wrong bytes; now return `{:indexed_hash, <<32 bytes>>}` per the Solidity spec rule for "all complex types."
- **`:string` decode NUL truncation** (1.2.0) — pre-existing in upstream since 2018. Any decoded string in cartouche flows that contained a NUL codepoint (`U+0000`) was silently truncated at the first NUL. Fix removes the helper entirely.
- **`encode_int/2` overflow guard** (1.1.0) — `int8`/`int16`/etc. were rejecting all valid values (including `0` for `int8`). If cartouche or any consumer was avoiding small int types because of this, that workaround can be dropped.
- **`dynamic?/1` crash on `T[0]`** (1.1.0) — zero-length fixed arrays no longer crash the layout query.

### Optional adoption — new hieroglyph public APIs

- `ABI.method_id/1` (1.1.0) — could replace the bespoke `Cartouche.Hash.keccak(ABI.FunctionSelector.encode(fn_sel))` selector derivation in `lib/mix/cartouche.gen.ex:149,416`. Equivalent semantics; smaller diff.
- `ABI.decode_error/2` (1.2.0) — Solidity 0.8.4+ custom-error revert decoding. Could replace the manual `error_abi -> ABI.decode(error_abi, error_data)` path in `lib/cartouche/rpc.ex:49`.
- `ABI.encode_packed/2` (1.2.0) — non-standard packed encoding for Merkle leaves and `keccak256(abi.encodePacked(...))`. Available if any future cartouche caller needs it (no current call site).
- `function` type encode/decode (1.3.0) — 24-byte external function pointer. Niche; only relevant if cartouche-generated bindings ever surface a `function` typed param.

**Acceptance:** the two `decode_structs` paths audited (with rationale recorded if no change made), bug-fix audit run for any production data that may have been silently miscompiled or truncated, optional new-API adoption taken or formally declined. Score is for the audit itself; if work is needed beyond verification, split into follow-up tasks here.

**Docs:** ROADMAP (this section's status); CHANGELOG `[Unreleased]` if any code change lands. No README/CLAUDE.md changes expected (cartouche public surface unchanged).

---

## Phase 12: Agent-economy descripex adoption

**Why:** Cartouche's API surface is well-documented for humans (most public functions have `@doc` + `@spec`) but invisible to AI agents — there is no machine-readable manifest, no MCP tool list, no progressive `describe()` discovery. Per the project's `agent-economy.md` include, libraries with ≥3 public modules should expose self-describing metadata via `descripex`. Cartouche has ~28 public modules (every `lib/cartouche/**.ex` not marked `@moduledoc false` and not under `lib/cartouche/contract/`); the cost is bounded (annotations are additive metadata) and the unlock is real: future MCP servers, agent frameworks, and EIP-8004 validators can introspect cartouche without scraping `@doc` strings.

`descripex 0.6.0` already resolves transitively via `hieroglyph 1.4`. Task 82 promotes it to a direct dep so consumer `mix.exs` files don't need to add it, stands up the `Cartouche` discoverable wrapper, and adds the validation test that polices annotated modules. Tasks 83-88 each pair a primary entry point with its natural co-domain helpers (e.g. RPC + the response decoders it returns; Solana Signer/Transaction + the instruction/PDA/ATA helpers they compose) — six `[P]`-eligible bundles spanning every public module in cartouche. Task 89 wires the static manifest export (`mix descripex.manifest`) and documents the discovery API in README. The phase ships as a complete annotation pass — no deferred tier; partial coverage would make `Cartouche.describe()` misleading.

**Coverage-gate exemption:** `api()` is metadata-only — it generates `@doc` (slot 4) + `@doc hints:` (slot 5) at compile time and adds `__api__/0,1` introspection functions. No runtime code path changes. Per `critical-rules.md` § "RAISE COVERAGE BEFORE MUTATING", this falls under the doc-only / metadata exemption. Each task body notes this explicitly so a future session does not get blocked unnecessarily on a tier coverage push that the work doesn't actually need.

**Excluded from scope:** generated modules under `lib/cartouche/contract/` (`Contract.IConsole`, generated `Contract.Sleuth`) are `@moduledoc false`. Annotating their generator template is the natural extension of existing **Task 50** (generator emits `@doc`/`@spec`); descripex annotations on generated bindings would ride along once Tasks 41/42/44/50 land. Not part of this phase.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 82 | Bootstrap descripex — direct dep + `Cartouche` discoverable wrapper + validation infra [D:2/B:3/U:6 → Eff:2.25] 🚀 | ⬜ | **Gates Tasks 83–89.** (1) Add `{:descripex, "~> 0.6"}` to `mix.exs` `deps` (currently transitive via `hieroglyph 1.4`; promote to direct so consumer `mix.exs` doesn't have to). Confirm `mix deps.get` is a no-op resolution-wise. (2) Create `lib/cartouche.ex` (currently no top-level wrapper) with `use Descripex.Discoverable, modules: @descripex_modules` and `@descripex_modules []` for now — Tasks 83+ register their modules as they land. Per `agent-economy.md` "App wrapper" pattern. (3) Add `test/descripex_validation_test.exs` — walks the registered module list, asserts every public function in each registered module has `:hints` slot 5 in `Code.fetch_docs/1` output. **Test must `flunk/1` with the unannotated function name** rather than skipping silently — per `feedback_never_hide_bugs.md` and the project's NEVER HIDE TEST FAILURES rule. The test starts trivially passing (zero registered modules) and grows teeth as Tasks 83+ register modules. (4) Acceptance: `mix deps.get` clean; `mix test test/descripex_validation_test.exs` green; `iex -S mix` then `Cartouche.describe()` returns the (initially empty) module list without raising. **Coverage gate: doc-only / metadata — exempt.** |
| 83 | Annotate `Cartouche.Signer` + `Cartouche.Keys` `[P]` `[CX]` [D:2/B:3/U:5 → Eff:2.0] 🚀 | ⬜ | **Blocked on Task 82.** Primary: `Cartouche.Signer` (11 defs, 7 docced) `namespace: "/ethereum/signer"`. Co-domain: `Cartouche.Keys` (1 def, 1 docced) — keypair helper consumed by Signer-adjacent flows. Add `use Descripex, namespace: "..."` and `api()` blocks before each public function (place `api()` *before* existing `@doc` so prose survives in slot 4; hints land in slot 5 — documented coexistence pattern). Param kinds: caller-supplied things → `:value`; anything that must be fetched first (e.g. nonce, chain id) → `:exchange_data` with `source:` pointer. Register both modules in the `Cartouche` wrapper's `@descripex_modules`. **Coverage gate: doc-only / metadata — exempt.** Acceptance: `mix test test/descripex_validation_test.exs` green; `Cartouche.describe(:signer)` and `:keys` return entries with non-empty `:hints`; `mix docs` clean; `mix dialyzer.json` no new warnings on touched files |
| 84 | Annotate `Cartouche.RPC` + response decoders bundle `[P]` `[CX]` [D:4/B:5/U:7 → Eff:1.5] 🚀 | ⬜ | **Blocked on Task 82.** Primary: `Cartouche.RPC` (31 defs, 25 docced) `namespace: "/ethereum/rpc"` — RPC method args (`block_number`, `address`, `transaction_hash`) annotate `:value` with explicit hex/decimal hints; block-tag args document the post-Task 60 union shape (`"latest"` / `"pending"` / integer); returns capture the `decode:` outcome shape per function. Co-domain (response/trace decoders RPC returns — agents need their shapes to consume RPC results): `Cartouche.Block` (2 defs + nested `Block.Withdrawal`), `Cartouche.Receipt` (2 defs + nested `Receipt.Log`), `Cartouche.FeeHistory` (1 def), `Cartouche.DebugTrace` (4 defs + nested `DebugTrace.StructLog`), `Cartouche.Trace` (7 defs + nested `Trace.Action`), `Cartouche.TraceCall` (3 defs). Each gets its own `namespace` segment under `/ethereum/`. **Coverage gate: doc-only / metadata — exempt.** Acceptance: same shape as Task 83, across all 7 modules |
| 85 | Annotate `Cartouche.Transaction` (incl. nested V1/V2 modules) `[P]` `[CX]` [D:3/B:4/U:6 → Eff:1.67] 🚀 | ⬜ | **Blocked on Task 82.** 21 public defs, 18 docced. `namespace: "/ethereum/transaction"`. Critical that V1 vs V2 (vs future V3/V4 from Tasks 31-32) struct shapes are differentiated in the manifest — agents need to know which constructor to call for which tx type. The `Transaction.V1` and `Transaction.V2` nested modules each get their own `namespace` segment (`/ethereum/transaction/v1`, `/ethereum/transaction/v2`); their `encode/1` / `decode/1` pairs are the highest-leverage targets. **Coverage gate: doc-only / metadata — exempt.** Acceptance: same shape as Task 83, against `Cartouche.Transaction` + V1 + V2 |
| 86 | Annotate `Cartouche.Solana.RPC` `[P]` `[CX]` [D:3/B:4/U:6 → Eff:1.67] 🚀 | ⬜ | **Blocked on Task 82.** 23 public defs, 19 docced. `namespace: "/solana/rpc"`. Solana RPC methods take base58 pubkeys and lamport-denominated values — annotate the encoding precisely so agents don't pass hex/wei by mistake. Returns are mostly maps (no custom struct decoders to bundle, unlike Ethereum RPC). **Coverage gate: doc-only / metadata — exempt.** Acceptance: same shape as Task 83, against `Cartouche.Solana.RPC` |
| 87 | Annotate Solana stack — `Solana.Signer` + `Solana.Transaction` + instruction/account helpers `[P]` `[CX]` [D:4/B:4/U:5 → Eff:1.13] 📋 | ⬜ | **Blocked on Task 82.** Primary: `Cartouche.Solana.Signer` (8 defs, 4 docced — annotation closes the doc gap as a side effect) and `Cartouche.Solana.Transaction` (11 defs, 10 docced — annotate the `sign_partial/2` empty-signer return shape from Task 57 explicitly). Co-domain (instruction/PDA/ATA builders that Transaction composes): `Cartouche.Solana.Keys` (5 defs), `Cartouche.Solana.PDA` (4 defs), `Cartouche.Solana.ATA` (3 defs), `Cartouche.Solana.Programs` (6 defs — program-ID constants), `Cartouche.Solana.SystemProgram` (3 defs), `Cartouche.Solana.TokenProgram` (5 defs), `Cartouche.Solana.Token` (3 defs). Each gets its own namespace segment under `/solana/`. **Coverage gate: doc-only / metadata — exempt.** Acceptance: same shape as Task 83, across all 9 modules |
| 88 | Annotate Ethereum utilities — `Hex` + `Erc20` + `Sleuth` + primitive bundle `[P]` `[CX]` [D:4/B:4/U:5 → Eff:1.13] 📋 | ⬜ | **Blocked on Task 82.** Primary utilities (high-traffic): `Cartouche.Hex` (38 defs, 27 docced) `namespace: "/ethereum/hex"` — encode/decode pairs are the API agents will misuse most; `Cartouche.Erc20` (8 defs, all docced) `namespace: "/ethereum/erc20"`; `Cartouche.Sleuth` (7 defs, 6 docced) `namespace: "/ethereum/sleuth"`. Co-domain (small primitive utilities used across Signer/Transaction/RPC — annotated here so they don't fall through the cracks): `Cartouche.Hash` (2 defs), `Cartouche.Address` (1 def), `Cartouche.Wei` (3 defs), `Cartouche.Chain` (2 defs), `Cartouche.Base58` (5 defs), `Cartouche.RecoveryBit` (5 defs). Each primitive gets its own namespace segment. **Coverage gate: doc-only / metadata — exempt.** Acceptance: same shape as Task 83, across all 9 modules |
| 89 | Wire `mix descripex.manifest` + document `Cartouche.describe()` in README `[CX]` [D:2/B:3/U:5 → Eff:2.0] 🚀 | ⬜ | **Blocked on Tasks 83-88 all landing** (every public module is in the manifest, no partial coverage). (1) Add a `mix.exs` alias (e.g. `manifest: ["descripex.manifest --pretty --output api_manifest.json"]`). (2) Treat `api_manifest.json` as generated; add a `.gitignore` entry and regenerate at release time, similar to `mix docs`. (3) Add an `## API discovery` section to `README.md` — three-line example showing `Cartouche.describe()` / `.describe(:rpc)` / `.describe(:rpc, :get_block_by_number)`. (4) Add a `Cartouche.Manifest` module wrapping `Descripex.Manifest.build(@modules)` for runtime consumers (HTTP endpoints, MCP servers — see `agent-economy.md` "Manifest & Progressive Disclosure"). (5) **Do not** add `api_manifest.json` to `package: files` — keep the package light; consumers who want the manifest can run `mix descripex.manifest` against the installed dep. **Coverage gate: not a code change — exempt.** Acceptance: `mix manifest` produces a non-empty `api_manifest.json`; README example is copy-pasteable; `Cartouche.Manifest.build/0` returns the same shape as `mix descripex.manifest --output -`; `Cartouche.describe()` returns every public, annotated module (excluding `@moduledoc false` modules — `Application`, `Assembly`, `Recover`, `Filter`, `OpenChain`, `VM`, `Contract.IConsole`, `Contract.Sleuth` — and generated bindings) |

**Acceptance (phase-level):** Tasks 82-89 all land. `Cartouche.describe()` returns every public, non-`@moduledoc false` module (~28 total). `mix descripex.manifest --pretty` produces a non-empty `api_manifest.json`. README documents the discovery API. The validation test in Task 82 enforces no public function in any registered module is left unannotated.

**Docs:** ROADMAP (this section's status); CHANGELOG `[Unreleased]` per task; README ## API discovery section in Task 89. CLAUDE.md unchanged (no convention shifts; agent-economy.md include already documents the design pattern).

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

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

## 🎯 Current Focus

**Phase 0 — ship `0.1.0`.** The code is ported under `Cartouche.*` (26 modules in `lib/cartouche/`). `mix.exs` still carries the inherited `1.6.1` from signet's fork point and needs to drop to `0.1.0-dev`. Test suite, dialyzer, and `mix docs` need a clean pass before publish. Nothing else is gated until `0.1.0` is on hex and onchain can resolve `{:cartouche, "~> 0.1"}`.

After `0.1.0`: Phase 1 (spec corrections — immediate onchain `@dialyzer` wins), then parallel work through Phases 2–9 as priority dictates.

---

## Phase 0: Ship `0.1.0`

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Reset `mix.exs` version `1.6.1` → `0.1.0-dev` [D:1/B:3/U:7 → Eff:5.0] 🎯 | ⬜ | One-line change. `CHANGELOG.md` already declares `0.1.x` as the active-dev line |
| 2 | Full `mix test.json --quiet` pass on the ported code [D:3/B:5/U:7 → Eff:2.0] 🚀 | ⬜ | Catch anything that broke in the signet→cartouche rename |
| 3 | `mix dialyzer.json --quiet` — inventory remaining `invalid_contract` warnings, confirm they match the pre-rename audit (Phases 1, 3, 4, 6 below) [D:2/B:3/U:6 → Eff:2.25] 🚀 | ⬜ | Regression check; warnings that weren't in the old audit need investigation |
| 4 | `mix docs` clean build with cartouche branding intact [D:2/B:3/U:5 → Eff:2.0] 🚀 | ⬜ | Verify module tree, `llms.txt` output, no broken links |
| 5 | Update `README.md` installation section — replace the "not recommended yet" placeholder with real install instructions [D:1/B:3/U:7 → Eff:5.0] 🎯 | ⬜ | Conditional on Task 6 — do right before publish |
| 6 | Tag `0.1.0`, publish to hex [D:1/B:5/U:8 → Eff:6.5] 🎯 | ⬜ | `mix hex.publish`. Acceptance: `mix hex.info cartouche` shows `0.1.0` |

**Acceptance:** onchain can `mix deps.update cartouche` against `{:cartouche, "~> 0.1"}` and resolve.

---

## Phase 1: Spec corrections (immediate onchain wins)

**Why:** These are the load-bearing fixes for onchain's `@dialyzer` suppressions. Every one is grounded in `mix dialyzer.json` output from the pre-rename audit (2026-04-21). All are surgical — spec-only edits, no runtime change.

### 1.1 `Cartouche.Util.RecoveryBit` — `:no_return` atom → `no_return()` type

Two specs declare the literal atom `:no_return` instead of the type `no_return()`. Dialyzer silently accepts unknown atoms in unions, so this isn't flagged — but the specs are semantically meaningless.

| Function | Line | Current `@spec` fragment | Should be |
|----------|------|--------------------------|-----------|
| `RecoveryBit.normalize/2` | `util.ex:388` | `\| :no_return` | `\| no_return()` |
| `RecoveryBit.normalize_signature/2` | `util.ex:419` | `\| :no_return` | `\| no_return()` |

| # | Task | Status | Notes |
|---|------|--------|-------|
| 7 | Fix both `:no_return` atom typos [D:1/B:2/U:6 → Eff:4.0] 🎯 | ⬜ | Two-line change in `lib/cartouche/util.ex`. No test needed |

### 1.2 `Cartouche.Util.to_wei/1` — narrow `number()` → `non_neg_integer()`

`@spec to_wei/1 :: number()` (line 257) but every clause returns `integer()` and amounts are non-negative by domain (wei is a discrete count).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 8 | Narrow `to_wei/1` return type [D:1/B:1/U:5 → Eff:3.0] 🎯 | ⬜ | One-line change. No test needed |

### 1.3 `Cartouche.Signer.sign_direct/4` — `mfa()` → `{module(), atom(), list()}`

Dialyzer reports `signer.ex:141 invalid_contract`. 3rd arg specced as `mfa()` (which Elixir defines as `{module(), atom(), arity :: non_neg_integer()}`) but the impl receives `{module(), atom(), args :: list()}`. The third element type does not overlap.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 9 | Replace `mfa()` with `{module(), atom(), [any()]}` in the `@spec` [D:1/B:3/U:5 → Eff:4.0] 🎯 | ⬜ | One-line + one doctest covering the `{m, f, args}` path |

### 1.4 `Cartouche.Hex` return-type specs

**Root cause:** private `Cartouche.Hex.decode_hex_/1` (`lib/cartouche/hex.ex:374`) returns `{:ok, t()} | :invalid_hex` but is specced `{:ok, t()} | :error`. All public callers inherit this:

| Function | Line | Current `@spec` | Actual return |
|----------|------|-----------------|---------------|
| `decode_hex/1` | 80 | `{:ok, t()} \| :error` | `{:ok, t()} \| :invalid_hex` |
| `decode_hex_number/1` | 245 | `{:ok, integer()} \| :error` | `{:ok, integer()} \| :invalid_hex` |
| `from_hex/1` | 91 | `t() -> String.t()` | `t() -> {:ok, t()} \| :invalid_hex` (alias for `decode_hex`) |
| `from_hex!/1` | 102 | `t() -> String.t()` | `t() -> t()` (alias for `decode_hex!`) |

Doctests and `@doc` examples already show the correct shape; only the `@spec` lines disagree. Fix is surgical — update the four specs, no implementation change.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 10 | Fix `decode_hex/1` + private `decode_hex_/1` spec [D:1/B:7/U:9 → Eff:8.0] 🎯 | ⬜ | Load-bearing for onchain Hex/ABI strips |
| 11 | Fix `decode_hex_number/1` spec [D:1/B:7/U:9 → Eff:8.0] 🎯 | ⬜ | Same module, bundle with Task 10 |
| 12 | Fix `from_hex/1` + `from_hex!/1` specs [D:1/B:7/U:9 → Eff:8.0] 🎯 | ⬜ | Confirmed by dialyzer: `hex.ex:91 invalid_contract` |
| 13 | Doctest coverage proving the real return shape for each of the four specs [D:2/B:7/U:9 → Eff:4.0] 🎯 | ⬜ | Required for upstream acceptance if pitched (see Phase 10); also grounds the local fix |

**Downstream impact once shipped in `0.1.x`:** onchain strips its `@dialyzer {:no_match, …}` blocks from `Onchain.Hex` and (via cascade through `Contract.call/5 → ABI.decode_response/2`) from the ABI / ERC / ENS / Multicall modules. Full downstream strip additionally needs the external `abi` fix tracked in Phase 10.

---

## Phase 2: `Cartouche.RPC.send_rpc/3` error-shape spec

**Why:** onchain carries `@dialyzer {:no_match, do_rpc: 3}` because the current spec promises `%{code: int, message: str}` for all errors, but `send_rpc/3` actually returns several other error shapes at runtime.

Confirmed runtime error shapes (`lib/cartouche/rpc.ex:84–203`, `lib/cartouche/util.ex:481–495`):

| Source | Returned shape |
|--------|----------------|
| Finch non-2xx | `{:error, %Finch.Response{}}` |
| Finch transport | `{:error, "[Cartouche] HTTP client error: …"}` (string) |
| Finch unknown | `{:error, "[Cartouche] Unknown error: …"}` (string) |
| Invalid JSON-RPC envelope | `{:error, %{code: -999, message: "…"}}` |
| Revert with decoded error (code 3) | `{:error, %{code:, message:, revert:, error_abi:, error_params:}}` (extra fields vs spec) |
| `decode: :hex` path with bad hex | bare `:invalid_hex` atom (not wrapped in `{:error, …}`) |
| Custom `decode:` fn raises | `{:error, "failed to decode `<method>` response: <inspect>"}` |

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 14 | Re-audit `send_rpc/3` `@spec` vs runtime error shapes on the ported code [D:3/B:6/U:7 → Eff:2.17] 🚀 | ⬜ | Confirm table above; some shapes may have been tightened in intervening signet commits before the fork |
| 15 | Widen error type (or split into tagged errors) with doctest coverage per shape [D:3/B:7/U:7 → Eff:2.33] 🚀 | ⬜ | Depends on Task 14. Keep `%{code, message}` as the JSON-RPC-error branch; union in the others |

**Blast radius** (from `mix reach.impact Cartouche.RPC.send_rpc/3`, pre-rename): 6 direct callers break on signature change (`get_balance/2`, `get_transaction_count/2`, `eth_block_number/1`, `eth_chain_id/1`, `set_filter/1`, `Cartouche.Filter.handle_info/2`), 1 transitive (`Cartouche.Signer.init/1`), no return-value dependents. Behavior-preserving spec-widening is low-risk; a union-type split needs all 6 direct callers to still type-check.

---

## Phase 3: `Cartouche.Trace` + `Cartouche.TraceCall` deserialize specs

**Why:** Dialyzer reports `trace.ex:408` and `trace_call.ex:124` as `invalid_contract`. The struct returned by `deserialize/1` has fields with union types (`nil | binary()`, `nil | <<_:160>>`, etc.) that the module's `@type t` declaration doesn't allow.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 16 | Update `Cartouche.Trace.@type t` (and nested `Cartouche.Trace.Action` type) to match dialyzer's inferred shape [D:3/B:2/U:4 → Eff:1.0] 📋 | ⬜ | Extend fields to `nil \| …` where runtime proves it |
| 17 | Update `Cartouche.TraceCall.@type t` analogously [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Piggybacks on Task 16 if `TraceCall` embeds `Trace.t()` |
| 18 | Unit tests exercising `deserialize/1` on representative JSON (with and without optional fields) [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Grounds the widened type in runtime behaviour |

---

## Phase 4: `Cartouche.Typed` internal-function specs

**Why:** Dialyzer reports `typed.ex:571` (`encode_value_map/3`) and `typed.ex:585` (`find_type/2`) as `invalid_contract`. Both specs completely disagree with the success typing — looks like copy-paste from a sibling function or a stale spec after a refactor.

- `encode_value_map/3`: spec returns a map; impl returns a `bitstring()`.
- `find_type/2`: spec returns `Typed.Type.t()`; impl returns a 2-tuple.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 19 | Read current impls, derive the true return types, rewrite both `@spec` lines [D:2/B:1/U:3 → Eff:1.0] 📋 | ⬜ | If these really are internal, add `@doc false` — keeps the `@spec` for dialyzer but removes from generated docs |
| 20 | Decide whether either fn is meant to be public API; if so, adjust impl to match the documented intent instead of changing the spec [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Judgment call; easier under fork ownership since we decide |

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
| 21 | Trace each Phase 5 warning back through `mix reach.deps` + `mix reach.slice` to find the first callee with `none()` success typing [D:5/B:3/U:3 → Eff:0.6] ⚠️ | ⬜ | Half-day to day. Only pursue if a concrete refactor target emerges |
| 22 | If root cause is a genuinely fixable spec narrowing: fix it. If it's structural (`raise`-heavy helpers): add `@dialyzer {:no_contracts, …}` locally in cartouche [D:2/B:4/U:6 → Eff:2.5] 🚀 | ⬜ | Local suppression is a valid terminal state |

---

## Phase 6: `Cartouche.VM.Context.init_from/2` spec

**Why:** `vm.ex:104 invalid_contract`. Spec says `:: t()` but success typing is the concrete struct literal, suggesting `@type t` is too loose or missing. Low-impact standalone.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 23 | Align `Cartouche.VM.Context.@type t` with dialyzer's inferred struct shape, or relax `init_from/2` to return `struct()` [D:2/B:1/U:3 → Eff:1.0] 📋 | ⬜ | Internal type. Bundle with Phase 5 if that opens a VM file anyway |

---

## Phase 7: Dependency freshness

Single-repo ownership simplifies this — we edit `mix.exs` and `mix.lock` directly, no dual-branch dance.

### 7.1 `google_api_cloud_kms` 0.38.1 → 0.43.0

`mix.exs` pins `~> 0.38.1` (resolves `< 0.39`). Cartouche uses this in `lib/cartouche/signer/cloud_kms.ex` via `cloudkms_..._get_public_key` and `cloudkms_..._asymmetric_sign`. Five minors of drift likely includes new key types (Ed25519, HMAC) or new methods worth surfacing.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 24 | Read `google_api_cloud_kms` CHANGELOG 0.38.1 → 0.43.0; flag breaking changes to `get_public_key` / `asymmetric_sign`, and any new key types relevant to Ethereum signing or attestation [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Read every minor; release notes are dense |
| 25 | Loosen constraint per findings; `mix deps.update google_api_cloud_kms`; verify `mix test` + `mix dialyzer.json` [D:2/B:3/U:4 → Eff:1.75] 🚀 | ⬜ | |
| 26 | If Task 24 surfaces a relevant new feature (Ed25519, HMAC, new auth), expose it in a follow-up feature task with docs + tests [D:5/B:4/U:4 → Eff:0.8] ⚠️ | ⬜ | Conditional |

### 7.2 `ex_doc` 0.31.1 → 0.40

`mix.exs` already carries `~> 0.40` (kept from the `:reach` requirement — `reach` pulls `makeup_elixir ~> 1.0` which conflicted with upstream's `ex_doc 0.31.1 → ~> 0.14`). No additional action needed beyond Task 4 verifying `mix docs` produces clean output.

### 7.3 `finch` 0.19 → 0.21

`mix.exs` pins `~> 0.19`. Cartouche uses Finch in `lib/cartouche/rpc.ex:167` and the error-normalizer in `util.ex:481`. Two minors of HTTP/2 and pool improvements — may simplify how we hand-build error strings from `%Finch.Error{}`.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 27 | Read `finch` CHANGELOG 0.19 → 0.21; identify options relevant to `Finch.request/3` or error classification [D:2/B:3/U:4 → Eff:1.75] 🚀 | ⬜ | |
| 28 | If Task 27 finds concrete wins (cleaner error variants, better pool config, HTTP/2 telemetry), adopt them with tests [D:3/B:3/U:3 → Eff:1.0] 📋 | ⬜ | Conditional |

### 7.4 Lockfile refresh

`ex_sha3`, `goth`, `junit_formatter`: constraints already permit newer versions; just `mix deps.update` and verify. Bundle into any other dep PR to keep the diff tidy.

---

## Phase 8: `Cartouche.Transaction.V2.encode/1` duplication

**Why:** `mix ex_dna` surfaces one Type I (exact) clone in `lib/cartouche/transaction.ex`: both `encode/1` clauses of `Cartouche.Transaction.V2` (unsigned at line 394, signed at line 423) share 10 lines of identical struct destructuring and the same `<<0x02>> <> ExRLP.encode([...])` prefix. The signed clause differs only by appending the normalized `signature_y_parity` / `signature_r` / `signature_s` triple and applying `Enum.map/2` to the access list.

Natural extraction: a private helper returning the prefix list from the struct. Each clause either encodes that list as-is (unsigned) or concatenates the signature triple before encoding (signed).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 29 | Verify both encode clauses have doctest coverage; add one to the unsigned clause if missing [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Refactors without test coverage are risky |
| 30 | Extract `defp unsigned_rlp_list/1`; rewrite both clauses to call it; verify byte-exact output equivalence via doctests [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | |

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
| Phase 1.1 — `RecoveryBit` `:no_return` typo | `fix:` | Pure win; no runtime effect; one line |
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

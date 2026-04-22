# Cartouche — Cleanup Backlog

Overflow tasks from the `mix credo --strict` / `mix doctor` / `mix dialyzer.json` audit run on 2026-04-22 against `development` branch.

**Scope:** this file covers items NOT already in [ROADMAP.md](ROADMAP.md). ROADMAP Phases 1–6 already track the 142 real-code dialyzer warnings. Everything here is net-new: credo style, doctor coverage gaps, the auto-generated-file noise floor, and Elixir 1.20 compile warnings.

**Scoring:** `[D:n/B:n/U:n → Eff:x]` per `~/.claude/includes/task-prioritization.md`.
- `B` = impact magnitude (noise reduction, CI signal-to-noise, onchain unblocks).
- `U` = unlock leverage (makes future dialyzer/credo/doctor runs actionable; enables a quality gate).

---

## Audit snapshot

| Tool | Total | Real / actionable | In ROADMAP | New (here) |
|---|---|---|---|---|
| `mix credo --strict` | 72 | 72 | 0 | **72** |
| `mix doctor` | 13 failing modules | 13 | 0 | **13** |
| `mix dialyzer.json` | 6 620 warnings | 142 real + 6 478 generated | 142 (Phases 1–6) | **6 478 + misc** |
| `mix compile` (1.20-rc.4) | 2 warnings | 2 | 0 | **2** |

The 6 478 `i_console.ex` warnings are one root cause amplified across 1 130 auto-generated decode functions. Fix the generator or the helper signature and most evaporate in a single change.

---

## 🎯 Current Focus

**Phase A — kill the noise floor.** Every `mix dialyzer.json` run is 98% noise from one generated file, which hides the 142 real findings Phases 1–6 already plan to fix. Phase A is 1–2 days of work that unblocks the signal.

Phase B (credo quick wins) and Phase C (Elixir 1.20 compile warnings) are small and independent — run them in parallel worktrees after Phase A lands.

Doctor coverage (Phase D) is the longest slog and purely QoL for consumers — defer until `0.1.0` ships and Phases 1–6 are closed.

---

## Phase A — Auto-generated file noise floor

- [ ] **A1: Root-cause the `i_console.ex` no_return / call cascade** [D:3/B:9/U:9 → Eff:3.0] 🎯
      `lib/cartouche/contract/i_console.ex` produces 5 715 `no_return` + 762 `call` + 1 `pattern_match` = 6 478 dialyzer warnings across ~1 130 auto-generated `decode_log_*` / `exec_vm_*` / `execute_*` functions. Likely one-or-two upstream causes (`Cartouche.Hex.hex!/1` success-typing, `Cartouche.RPC.execute_trx/3` spec, or `ABI.decode/3` inferred to `none()`). Use `mix reach.impact` on the shared callees to find the origin, fix the one signature, regenerate. Verify with `mix dialyzer.json --summary-only` showing i_console count →  ≪100.

- [ ] **A2: Regenerate `i_console.ex` after A1 and commit the diff** [D:1/B:3/U:5 → Eff:4.0] 🎯
      `mix cartouche.gen` (or whatever command generated it — see `lib/mix/cartouche.gen.ex`). Confirm the @moduledoc banner ("auto-generated … any changes may be lost") still matches — no manual edits.

- [ ] **A3: If A1 can't drop warnings below ~50, add `.dialyzer_ignore.exs` pattern for `i_console.ex`** [D:2/B:5/U:7 → Eff:3.0] 🎯
      Fallback only. Add a file-scoped ignore entry with a comment linking back to A1. DialyzerJSON honours `.dialyzer_ignore.exs` (see `dialyzer-json.md`) — ignored items move to `summary.skipped`, keeping the signal clean.

---

## Phase B — Credo quick wins (lib)

50 lib findings. Group by effort.

### B1: Mechanical fixes — batch PR [D:2/B:3/U:5 → Eff:2.0] 🚀

- [ ] TrailingWhiteSpace — `lib/cartouche/receipt.ex:26` (1)
- [ ] ExpensiveEmptyEnumCheck — `lib/mix/cartouche.gen.ex:746` (1) — `Enum.count/1` → `Enum.empty?/1`
- [ ] MaxLineLength — `block.ex:67`, `receipt.ex:20,30,119` (4). Some are long ABI/JSON strings that likely can't wrap — add `# credo:disable-for-next-line` with justification where wrapping breaks clarity.
- [ ] AliasUsage — `lib/cartouche/solana/signer.ex:109`, `lib/cartouche/vm.ex:47` (×2) (3)
- [ ] FunctionNames — `lib/cartouche/base58.ex:53` (1) — one camelCase fn to rename OR add `# credo:disable-for-lines:N` if it matches an external protocol name.

### B2: Test-support external-method names — allowlist, don't rename [D:1/B:3/U:5 → Eff:4.0] 🎯

- [ ] `test/support/client.ex` has 17 `FunctionNames` violations — `eth_getBalance`, `eth_newFilter`, etc. These mirror JSON-RPC method names on purpose. Add a scoped disable to the module via `# credo:disable-for-this-file Credo.Check.Readability.FunctionNames` with a one-line comment explaining the convention mirror. Never rename — they're a test fixture for wire-compatibility.

### B3: Test AliasUsage [D:1/B:1/U:3 → Eff:2.0] 📋

- [ ] 7 AliasUsage warnings in `test/` — mechanical `alias` hoisting to top of module. Defer to B1's PR or a separate test-cleanup pass.

### B4: Nesting depth violations — read before fixing [D:5/B:3/U:3 → Eff:0.6] ⚠️

16 lib nesting violations. Most are `case` inside `with` or nested `if`. Walk each with a judgment call:
- [ ] `rpc.ex:105, 194, 1399, 1588` — RPC dispatch; likely ok-as-is, extract helper only if it improves read
- [ ] `vm.ex:510, 554, 757` — VM interpreter; depth 5 at 757 may justify extraction
- [ ] `assembly.ex:335`, `open_chain.ex:87`, `sleuth.ex:142`, `solana/token.ex:56,99`, `solana/transaction.ex:208`, `typed.ex:588`, `mix/cartouche.gen.ex:153,337`
- Rule: extract only if the inner block is named/reusable. Otherwise `# credo:disable-for-next-line Credo.Check.Refactor.Nesting` with a one-line reason.
- Do NOT pre-extract to satisfy credo — that produces one-use helpers and hurts readability.

### B5: CyclomaticComplexity — design-level [D:7/B:3/U:3 → Eff:0.43] ⚠️

8 lib violations, including:
- [ ] `assembly.ex:503` (complexity **84**) — likely the opcode dispatch
- [ ] `vm.ex:590` (complexity **77**) — likely the VM opcode interpreter
- [ ] `mix/cartouche.gen.ex:247` (complexity **55**) — codegen dispatch
- [ ] `rpc.ex:42, 86, 1350`, `sleuth.ex:104`, `mix/cartouche.gen.ex:170` (10–12)

Big dispatch tables on opcodes/methods are legitimate — the alternative is a scattered map of `{opcode => fn}` that's worse to read. Recommend per-function `@credo :disable` with a note, rather than forced refactor. Treat the 10–12 mid-tier ones case by case.

### B6: FunctionArity 9–12 in `transaction.ex` [D:5/B:3/U:3 → Eff:0.6] ⚠️

- [ ] `transaction.ex:285 (9), 312 (12), 790 (9), 865 (9)` — transaction-field encoders. Ethereum transaction structs have 9–12 fields; accepting them positionally mirrors the underlying spec. Options: (a) accept a struct and pattern-match in head (best), (b) credo-disable with note. Decide per-function.

### B7: Exception naming consistency [D:3/B:1/U:3 → Eff:0.67] ⚠️ DISCUSS

- [ ] `ExceptionNames`: `Cartouche.Hex.HexError`, `Cartouche.VM.VmError` clash with the `Invalid*` strategy used elsewhere (`InvalidAssembly`, `InvalidCode`, `InvalidOpcode`, `InvalidFileError`). Rename is a **breaking API change** (`HexError` appears in public `@doc` examples). Options:
  1. Keep names, credo-disable in both files with a note ("public API name — frozen").
  2. Rename `Invalid*` → `*Error` for internal consistency (more breakage, wider blast).
  3. Accept inconsistency permanently, raise credo's priority threshold for this check.
- Recommendation: **(1)**. Don't break public API for a style check.

### B8: RaiseInsideRescue [D:1/B:3/U:3 → Eff:3.0] 🚀

- [ ] `lib/cartouche/sleuth.ex:204` — change `raise` inside rescue → `reraise __STACKTRACE__` to preserve origin stack. Real correctness win.

### B9: TagTODO [D:0/B:0/U:0] — SKIP

- 2 lib + 1 test `TagTODO` findings are working as designed (project policy is `TODO:` prefix REQUIRED for tracked tech debt — see `~/.claude/includes/development-philosophy.md`). These are informational, not actionable.

---

## Phase C — Elixir 1.20-rc.4 compile warnings

- [ ] **C1: Pin bitstring size vars in `solana/transaction.ex`** [D:1/B:5/U:7 → Eff:6.0] 🎯
      Lines 346, 349 in `read_instructions/3` — 1.20 requires `^num_accounts` / `^data_len` when reusing a match-binding as a bitstring size. One-line fix × 2. Blocks a clean 1.20 compile once 1.20 ships stable.

---

## Phase D — Doctor coverage (defer)

**Status:** 5.5% `@doc` / 4.0% `@spec` coverage. 100% `@moduledoc`. Fails the 50% threshold.

Failing modules ranked by function count × current gap:

| Module | Functions | @doc | @spec | Treatment |
|---|---|---|---|---|
| `Cartouche.Contract.IConsole` | 3 816 | 0% | 0% | Generator-side fix (see D1) |
| `Mix.Tasks.Cartouche.Gen` | 24 | 4% | 4% | Codegen task; docs on `run/1` + private-fn `@spec` |
| `Cartouche.Contract.Sleuth` | 22 | 0% | 0% | Codegen target; likely also auto-generated |
| `Cartouche.VM` | 19 | 11% | 0% | Core VM module; invest in docs, ties to ROADMAP Phase 5/6 |
| `Cartouche.Sleuth` | 6 | 0% | 0% | Unused — see D3 (some fns already flagged unused_fun) |
| `Cartouche.VM.{Operations, Memory, FFIs, Context, ExecutionResult}` | 1–4 each | 0% | 0–100% | Internal types/helpers; `@moduledoc false` is legitimate if internal |
| `Cartouche.OpenChain.API` | 3 | 33% | 67% | Small gap; fill in |
| `Cartouche.Filter.Log` | 1 | 0% | 0% | One fn; fill in |

### Tasks

- [ ] **D1: Add `@doc` + `@spec` emission to `Cartouche.Contract.IConsole` generator** [D:5/B:7/U:7 → Eff:1.4] 📋
      Edit `lib/mix/cartouche.gen.ex` to generate `@doc` (pulled from the Solidity NatSpec where present, else function name) and `@spec` from the ABI types. Regenerate `i_console.ex`. This alone fixes the single biggest module and lifts overall coverage above 50%.

- [ ] **D2: `@moduledoc false` for genuine internals** [D:1/B:3/U:3 → Eff:3.0] 🚀
      `Cartouche.VM.{Operations, Memory, FFIs, Context, ExecutionResult}`, `Cartouche.Filter.Log` — audit which are public. Non-public get `@moduledoc false`, which doctor exempts. One line each.

- [ ] **D3: Document or remove `Cartouche.Sleuth` internals** [D:3/B:3/U:3 → Eff:1.0] 📋
      3 fns (`try_decode/3`, `try_decode_bytes/1`, `postprocess/3`) are flagged `unused_fun` by dialyzer. Delete if dead, document if reachable via dynamic dispatch. See E1.

- [ ] **D4: Fill remaining small gaps** [D:3/B:3/U:3 → Eff:1.0] 📋
      `Cartouche.OpenChain.API` (3 fns), `Mix.Tasks.Cartouche.Gen` public `run/1`, `Cartouche.VM` core API. Tie to ROADMAP Phase 4/5 when those files are open anyway.

---

## Phase E — Dialyzer items NOT in ROADMAP

ROADMAP Phases 1–6 cover `invalid_contract` + most `no_return` / `call` / `pattern_match` on `hex.ex`, `rpc.ex`, `signer.ex`, `trace.ex`, `trace_call.ex`, `typed.ex`, `erc_20.ex`, `vm.ex`. These are the leftovers:

- [ ] **E1: Remove 13 `unused_fun` warnings** [D:2/B:3/U:5 → Eff:2.0] 🚀
      - `sleuth.ex`: `try_decode/3`, `try_decode_bytes/1`, `postprocess/3` — verify dead, delete
      - `vm.ex`: `pop2_and_push/2`, `unsigned_op1/2`, `unsigned_op2/2`, `unsigned_op3/2`, `signed_op2/2`, `unsigned_signed_op2/2`, `static_call/1`, `pop_call_args/1`, `word_to_address/1`, `run_code/2` — likely scaffolding for incomplete VM opcodes. Delete or mark `@dialyzer {:nowarn_function, ...}` with a TODO(Phase 5) pointer. Ties to ROADMAP Phase 5 investigation.

- [ ] **E2: 3 `unknown_type` warnings** [D:1/B:3/U:3 → Eff:3.0] 🚀
      Inventory and fix — usually a stale `@spec` referencing a renamed type. Small.

---

## Execution order (suggested)

1. **Phase C** (1 hr) — compile clean first. No dependencies.
2. **Phase A1 + A2** (1–2 days) — biggest single noise reduction. Must land before real-code dialyzer phases pay off.
3. **ROADMAP Phases 1–6** — existing plan, now against a quiet dialyzer.
4. **Phase B1 + B2 + B8** (half day) — batch credo quick wins as one PR.
5. **Phase E1 + E2** (half day) — clean up dialyzer tail.
6. **Phase B4–B7** — case-by-case, bundle with whatever file is open.
7. **Phase D** — after `0.1.0` ships.

A–C + E1 + E2 roughly = 3 focused days. B and D are background work to bundle opportunistically.

# Cartouche (ZenHive fork)

@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md

<!--
Selective-load (Opus 4.8 — see setup-guide.md § "Skills vs Includes"):
the eager floor is critical-rules + harness-workflow + onchain-workspace
(harness workspace add-on — 7-repo roster + dependency shape).

Delegation is via the harness engine. harness-workflow.md is @-imported as the
portfolio-wide implement→review→land contract (cartouche is harness-driven);
the harness-driver skill stays skill-on-demand for the MCP/API surfaces. The
legacy Linear + Codex/Cursor stack is intentionally not loaded.

Everything else is skill-on-demand — Opus self-invokes when the situation
fires, and the hard parts are hook-enforced independently:
  worktree-workflow      → workflow:git-worktrees
  task-prioritization    → tasks:roadmap-planning
  task-writing           → tasks:task-writing
  rmap                   → tasks:rmap
  workflow-philosophy    → workflow:workflow-philosophy
  code-style             → elixir:code-style
  development-philosophy → elixir:development-philosophy
  development-commands   → elixir:development-commands
  ex-unit-json           → elixir:ex-unit-json
  dialyzer-json          → elixir:dialyzer-json
  upstream-pr-workflow   → workflow:upstream-pr-workflow
  elixir-setup           → elixir:elixir-setup
  web-command / agent-economy / reach → elixir:*

Note: AGENTS.md is generated from this file (sync-agents-md.sh inlines the
@-imports) for any tool that reads the generic AGENTS.md convention but has no
skill system. We don't run Linear/Codex/Cursor cloud delegation here — harness
is the only dispatch path — so AGENTS.md has no cloud-agent consumer today;
it's kept as a low-cost convention surface. The Elixir convention set is also
enforced by the CI harness (.github/workflows/harness.yml).
-->

forked from https://github.com/hayesgm/signet

## Delegation roster

Portfolio default — carried by `harness-workflow.md` § "Delegation roster — opus last" (`@`-imported above): assign dispatchable tasks **cursor / codex / grok first, opus only if needed** (opus tokens are precious). Cartouche takes the default; no project override.

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Canonical gate:** `mix precommit.full` (and its alias `mix ci`) — the comprehensive pass the harness reviewer's `check_command` runs. Fast local loop: `mix precommit` (skips the cold-PLT dialyzer + full coverage). Both are defined in `mix.exs` aliases and pinned to `MIX_ENV=test` via `def cli`.
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags; ExSlop plugin enabled in `.credo.exs`), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --config`, `test.json --cover --cover-threshold 85 --exclude integration`, `dialyzer`. CI (`.github/workflows/harness.yml`) mirrors these as separate steps (keeping its own `MIX_ENV=dev` dialyzer with the cached `priv/plts` PLT and the `.sobelow-skips` drift check).
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design — this is NOT a build failure.** Parse the JSON for real failures; never flag the envelope itself. Plain `mix dialyzer` is the authoritative dialyzer check when the JSON encoder can't serialize a warning shape (it's what the gate and CI run).
- **The gate's dialyzer runs under `MIX_ENV=test`, so it compiles and analyzes `test/support/` — GitHub CI's `MIX_ENV=dev` dialyzer does not.** A clean `mix dialyzer` (dev) does **not** imply a clean `mix ci`. When `mix ci` fails dialyzer but plain `mix dialyzer` is green, the culprit is almost always a `test/support/` module. Reproduce the gate's view with `MIX_ENV=test mix dialyzer`.

## Generated contract fixtures (`mix cartouche.gen`)

The contract wrappers under `lib/cartouche/contract/*.ex` (i_console, sleuth) and the test fixtures under `test/support/cartouche/contract/*.ex` (ierc20, rock, block_number) are **generated** by `mix cartouche.gen` from ABI JSON in `test/abi/*.json`. They are committed, not regenerated in CI — so they **drift stale** when the generator evolves but a fixture isn't re-emitted.

- **The dialyzer trap:** an older generator built call/estimate wrappers on `%V2{}` (`build_trx_* -> %V2{destination, data}`). But `V2.t()` types the gas/fee/nonce/`access_list` fields as **non-nilable** while `defstruct` defaults them to `nil`, so `%V2{destination, data}` is **not** a valid `V2.t()`, and `Cartouche.RPC.call_trx`/`estimate_gas` (domain `V1.t()|V2.t()|Call.t()`) type those wrappers as `none()` → "no local return" + "invalid type specification" warnings. The current generator emits `%Call{}` (whose `Call.t()` is nil-tolerant), which is clean. The `lib/` outputs are credo-excluded (`~r"lib/cartouche/contract/"`) and were kept current; `test/support/` fixtures are credo-*included* and dialyzed in test env, so a stale one there fails `mix ci` (e.g. ierc20, fixed in `5f4086f` — was 73 warnings).
- **Fix a stale fixture by regenerating, not hand-editing** (`critical-rules.md` → fix the generator/its input, not the output): `mix cartouche.gen --prefix Cartouche.Contract --out <scratch>/ test/abi/<Name>.json`, then `mix format <file>`, copy over the committed fixture, and **restore the file-level `# credo:disable-for-this-file Credo.Check.Readability.MaxLineLength`** (the generator does not emit it; wrapped event topic-0 hashes exceed 120 chars). Verify with `MIX_ENV=test mix dialyzer` (0 warnings) and `mix ci`.
- **Tell-tale of stale-but-harmless drift:** missing `alias V1/V2`, `@doc false`/`@spec ... :: term()` instead of descriptive `@doc`/real specs, no `abi/0`. These are cosmetic (rock, block_number currently) — they pass dialyzer/credo and do **not** block the gate; only the `%V2{}` shape above breaks it. Don't churn passing fixtures just to refresh doc richness.

## Hook-flagged issues

When our PostToolUse hooks flag issues on files you touched (credo, format, dialyzer, etc.), fix them in this commit — including pre-existing flags unrelated to your change. See `critical-rules.md` → "FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH". Touched-file scope only, not project-wide.

## Sobelow workflow

After fixing a sobelow finding (or otherwise wanting to refresh `.sobelow-skips`), regenerate the suppression file from live state:

```bash
mix sobelow --mark-skip-all
```

That writes a fresh `.sobelow-skips` containing fingerprints for whatever sobelow flags right now. Resolved findings drop out automatically; new ones get added. Confirm with `mix sobelow` (clean output = all findings are accounted for).

`.sobelow-skips` is **tracked** — it is the project's accepted-pending-fix security baseline. Each fingerprint should map to a ROADMAP task that, when shipped, will resolve the finding (currently: Task 48 for the `Cartouche.Sleuth` `String.to_atom` cluster; Tasks 41/42/50/59-gen for the generator's `String.to_atom` and `File.{read!,mkdir_p!,write!}` paths). Fingerprints are deterministic (file:line + rule), so the file doesn't churn unless code or sobelow rules change. The CI harness (`.github/workflows/harness.yml`) runs `mix sobelow` against `.sobelow-conf` (`exit: "Low"`, `skip: true`) on every PR — without `.sobelow-skips` tracked, every CI run would fail on the accepted-pending-fix findings, so the file must be in version control. A second workflow (`.github/workflows/code-scanning.yml`) additionally uploads `mix sobelow --format sarif` output to GitHub's code-scanning view (reporting only, `continue-on-error` — not a gate). Don't hand-edit; regenerate via `mix sobelow --mark-skip-all` when fingerprints change.

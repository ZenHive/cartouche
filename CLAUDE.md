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

## Hook-flagged issues

When our PostToolUse hooks flag issues on files you touched (credo, format, dialyzer, etc.), fix them in this commit — including pre-existing flags unrelated to your change. See `critical-rules.md` → "FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH". Touched-file scope only, not project-wide.

## Sobelow workflow

After fixing a sobelow finding (or otherwise wanting to refresh `.sobelow-skips`), regenerate the suppression file from live state:

```bash
mix sobelow --mark-skip-all
```

That writes a fresh `.sobelow-skips` containing fingerprints for whatever sobelow flags right now. Resolved findings drop out automatically; new ones get added. Confirm with `mix sobelow` (clean output = all findings are accounted for).

`.sobelow-skips` is **tracked** — it is the project's accepted-pending-fix security baseline. Each fingerprint should map to a ROADMAP task that, when shipped, will resolve the finding (currently: Task 48 for the `Cartouche.Sleuth` `String.to_atom` cluster; Tasks 41/42/50/59-gen for the generator's `String.to_atom` and `File.{read!,mkdir_p!,write!}` paths). Fingerprints are deterministic (file:line + rule), so the file doesn't churn unless code or sobelow rules change. The CI harness (`.github/workflows/harness.yml`) runs `mix sobelow` against `.sobelow-conf` (`exit: "Low"`, `skip: true`) on every PR — without `.sobelow-skips` tracked, every CI run would fail on the accepted-pending-fix findings, so the file must be in version control. A second workflow (`.github/workflows/code-scanning.yml`) additionally uploads `mix sobelow --format sarif` output to GitHub's code-scanning view (reporting only, `continue-on-error` — not a gate). Don't hand-edit; regenerate via `mix sobelow --mark-skip-all` when fingerprints change.

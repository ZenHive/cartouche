# Cartouche (ZenHive fork)

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md

@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/web-command.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/reach.md
@~/.claude/includes/agent-economy.md
@~/.claude/includes/upstream-pr-workflow.md


forked from https://github.com/hayesgm/signet

## Hook-flagged issues

When our PostToolUse hooks flag issues on files you touched (credo, format, dialyzer, etc.), fix them in this commit — including pre-existing flags unrelated to your change. See `critical-rules.md` → "FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH". Touched-file scope only, not project-wide.

## 🚨 Never delegate dialyzer-scoped tasks to cloud agents

**Cartouche is too big for the cloud-agent VMs to run `mix dialyzer` reliably — Cursor / Codex VMs OOM-crash mid-PLT-build.** Do NOT create Linear issues whose acceptance criteria require running `mix dialyzer` / `mix dialyzer.json` on the cloud agent's side.

This blocks `[CSR]` (Cursor) and `[CX]` (Codex) delegation for any task whose primary work product is "fix N dialyzer warnings" or "narrow `@spec` so dialyzer infers X."

**How to apply:**

- Dialyzer-scoped ROADMAP tasks (Phase 4 `Cartouche.Typed` impl tightenings, Phase 5 `none()` cascade investigation, Phase 6 `init_from/2` spec work, any "tighten `@spec` so dialyzer narrows" task) → **stay local**. Run `mix dialyzer.json --quiet` against the host's PLT and ship the fix from this Claude Code session.
- Spec / `@doc false` / `@dialyzer {:no_contracts, …}` annotation work that doesn't *require* dialyzer to verify (i.e. the agent can compile, run `mix test.json`, run `mix credo --strict`, and trust local follow-up to confirm dialyzer impact) → still delegable, but the issue body must explicitly note "dialyzer verification happens locally post-merge — do NOT attempt `mix dialyzer` in the agent harness; PLT build will OOM."
- Mixed-scope tasks (some dialyzer, some not) → split. The non-dialyzer parts can ship via Linear; the dialyzer parts come back to local.

**Why:** observed empirically across multiple Cursor and Codex Cloud sessions on cartouche — PLT incremental builds for the full cartouche dep set (ExRLP, Curvy, ABI, Jason, Decimal, etc. plus all of cartouche's own modules) consistently exceed the cloud VM's memory budget. The agent reports back with a partial PR or a failed harness run, and the local reviewer ends up rebuilding the PLT and re-running dialyzer anyway. Net negative versus just doing the work locally.

**Affected open ROADMAP tasks** (do NOT promote these to Linear):

- Tasks 21+22 — Phase 5 `none()` cascade — *already deployed as INE-42, but acceptance criteria deliberately scope to `mix dialyzer.json` snapshots that will be re-verified locally; the agent is annotating only.* Future similar tasks: keep local.
- Task 76 — Restore dialyzer to CI on a larger runner — meta-task about CI infrastructure; itself stays local until resolved (its resolution is what would unlock cloud-agent dialyzer in the first place).
- Task 98 — Tighten `Cartouche.Typed.encode_value_map/3` impl so dialyzer infers `binary()` — pure dialyzer-narrowing work; stays local.

**When this lifts:** Task 76 (dialyzer-on-larger-runner CI) lands AND we verify a cloud-agent VM completes a full PLT build. Until both are true, treat this rule as hard.

## Sobelow workflow

After fixing a sobelow finding (or otherwise wanting to refresh `.sobelow-skips`), regenerate the suppression file from live state:

```bash
mix sobelow --mark-skip-all
```

That writes a fresh `.sobelow-skips` containing fingerprints for whatever sobelow flags right now. Resolved findings drop out automatically; new ones get added. Confirm with `mix sobelow` (clean output = all findings are accounted for).

`.sobelow-skips` is **tracked** — it is the project's accepted-pending-fix security baseline. Each fingerprint should map to a ROADMAP task that, when shipped, will resolve the finding (currently: Task 48 for the `Cartouche.Sleuth` `String.to_atom` cluster; Tasks 41/42/50/59-gen for the generator's `String.to_atom` and `File.{read!,mkdir_p!,write!}` paths). Fingerprints are deterministic (file:line + rule), so the file doesn't churn unless code or sobelow rules change. The CI harness (`.github/workflows/harness.yml`) runs `mix sobelow` against `.sobelow-conf` (`exit: "Low"`, `skip: true`) on every PR — without `.sobelow-skips` tracked, every CI run would fail on the accepted-pending-fix findings, so the file must be in version control. Don't hand-edit; regenerate via `mix sobelow --mark-skip-all` when fingerprints change.

#!/bin/zsh
# Task 114 mutation-adequacy campaign.
#
# ONE invocation over the whole surface, deliberately: --coverage-guided builds
# its line index by running `mix test.json <file> --cover` once per test file,
# serially, with no cache (deps/muex/lib/muex/coverage.ex Coverage.collect/3).
# Per-module invocations therefore pay that full-suite cost 13 times over —
# which is what exhausted the harness run's lifetime budget.
#
# Exhaustive: --no-filter --no-optimize, all 18 mutators. --coverage-guided
# only narrows which EXISTING tests run per mutant; it never drops a mutant.
set -u
cd /Users/efries/_DATA/worktrees/cartouche/114 || exit 1
export MIX_ENV=test

MUTATORS=arithmetic,boolean,case_clause,comparison,cond_clause,conditional,enum_semantics,extended_math,function_call,guard,invert_negatives,literal,map_semantics,negate_conditionals,pipe,return_value,statement_deletion,with_clause

FILES='lib/cartouche/transaction.ex,lib/cartouche/transaction/*.ex,lib/cartouche/signer.ex,lib/cartouche/signer/*.ex,lib/cartouche/recover.ex,lib/cartouche/recovery_bit.ex'

OUT=.mutation/results
mkdir -p "$OUT"

echo "=== CAMPAIGN START $(date +%H:%M:%S)"
t0=$(date +%s)
mix muex --files "$FILES" --test-paths test \
  --mutators "$MUTATORS" \
  --no-filter --no-optimize --coverage-guided \
  --concurrency 8 --timeout 60000 --fail-at 0 --format json \
  > "$OUT/campaign.raw" 2> "$OUT/campaign.err"
rc=$?
t1=$(date +%s)
python3 - "$OUT/campaign.raw" "$OUT/campaign.json" <<'PY'
import sys
raw = open(sys.argv[1]).read()
i = raw.find('{')
open(sys.argv[2], 'w').write(raw[i:] if i >= 0 else '')
PY
echo "=== CAMPAIGN DONE rc=$rc $(( t1 - t0 ))s $(date +%H:%M:%S)"

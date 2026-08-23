#!/bin/zsh
# Task 114 verification pass: re-measure the three files that carried all 55
# unexecuted mutants, with the gap-closing tests in place. Same flags as the
# baseline campaign so the numbers are comparable.
set -u
cd "${0:A:h}/.." || exit 1
export MIX_ENV=test

MUTATORS=arithmetic,boolean,case_clause,comparison,cond_clause,conditional,enum_semantics,extended_math,function_call,guard,invert_negatives,literal,map_semantics,negate_conditionals,pipe,return_value,statement_deletion,with_clause
FILES='lib/cartouche/recovery_bit.ex,lib/cartouche/transaction/v3.ex,lib/cartouche/transaction/v4.ex'
OUT=.mutation/results
mkdir -p "$OUT"

echo "=== VERIFY START $(date +%H:%M:%S)"
t0=$(date +%s)
mix muex --files "$FILES" --test-paths test \
  --mutators "$MUTATORS" \
  --no-filter --no-optimize --coverage-guided \
  --concurrency 8 --timeout 60000 --fail-at 0 --format json \
  > "$OUT/verify.raw" 2> "$OUT/verify.err"
rc=$?
t1=$(date +%s)
python3 - "$OUT/verify.raw" "$OUT/verify.json" <<'PY'
import sys
raw = open(sys.argv[1]).read()
i = raw.find('{')
open(sys.argv[2], 'w').write(raw[i:] if i >= 0 else '')
PY
echo "=== VERIFY DONE rc=$rc $(( t1 - t0 ))s $(date +%H:%M:%S)"

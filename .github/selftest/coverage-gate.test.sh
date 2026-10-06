#!/usr/bin/env bash
# Executes java-test.yml's "Check coverage threshold" script verbatim against a
# table of inputs. The script is extracted from the workflow rather than copied,
# so the test cannot drift from what consumers run.
set -euo pipefail
cd "$(dirname "$0")/../.."

SCRIPT=$(python3 - <<'PY'
import yaml
wf = yaml.safe_load(open('.github/workflows/java-test.yml'))
steps = wf['jobs']['test']['steps']
step = next(s for s in steps if s.get('name') == 'Check coverage threshold')
body = step['run']
assert '${{' not in body, 'run body must read env vars only'
print(body)
PY
)

fails=0
# case <name> <expected: pass|fail> KEY=VALUE...
case_() {
  local name=$1 expect=$2; shift 2
  local rc=0
  # -eo pipefail: the step now runs under `shell: bash`, which GitHub resolves to
  # `bash --noprofile --norc -eo pipefail {0}`. Match those flags, not bare `bash -c`.
  env -i PATH="$PATH" GITHUB_STEP_SUMMARY=/dev/null \
      LINE_THRESHOLD=0 INSTR_THRESHOLD=0 BRANCH_THRESHOLD=0 \
      LINE_PCT= INSTR_PCT= BRANCH_PCT= HAS_JACOCO_LOG=false \
      "$@" bash -eo pipefail -c "$SCRIPT" >/dev/null 2>&1 || rc=$?
  local got=pass; [ "$rc" -eq 0 ] || got=fail
  if [ "$got" = "$expect" ]; then echo "ok   $name"; else echo "FAIL $name (expected $expect, got $got)"; fails=$((fails+1)); fi
}

case_ 'disabled gate passes'                   pass LINE_THRESHOLD=0  LINE_PCT=10
case_ 'integer above passes'                   pass LINE_THRESHOLD=80 LINE_PCT=85.2
case_ 'integer below fails'                    fail LINE_THRESHOLD=80 LINE_PCT=79.9
case_ 'decimal threshold below fails'          fail LINE_THRESHOLD=80.5 LINE_PCT=80.4
case_ 'decimal threshold above passes'         pass LINE_THRESHOLD=80.5 LINE_PCT=80.6
case_ 'equal passes'                           pass LINE_THRESHOLD=80 LINE_PCT=80
case_ 'empty coverage with threshold fails'    fail LINE_THRESHOLD=80 LINE_PCT=
case_ 'garbage coverage with threshold fails'  fail LINE_THRESHOLD=80 LINE_PCT=N/A
case_ 'empty coverage, gate off, passes'       pass LINE_THRESHOLD=0  LINE_PCT=
case_ 'instruction below fails'                fail INSTR_THRESHOLD=70 INSTR_PCT=69 HAS_JACOCO_LOG=true
case_ 'instruction ignored without log'        pass INSTR_THRESHOLD=70 INSTR_PCT=10 HAS_JACOCO_LOG=false
case_ 'branch decimal below fails'             fail BRANCH_THRESHOLD=60.5 BRANCH_PCT=60 HAS_JACOCO_LOG=true
case_ 'branch empty with log fails'            fail BRANCH_THRESHOLD=60 BRANCH_PCT= HAS_JACOCO_LOG=true

echo "$fails failing case(s)"
exit $((fails > 0))

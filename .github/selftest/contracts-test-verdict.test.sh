#!/usr/bin/env bash
# Executes contracts-test.yml's "Run contract tests" and "Check test results"
# verbatim. The run step used to drop the runner's exit code with `|| true` and
# the verdict came from Mocha's "N failing" line alone, so a compile error, a
# crash, or a non-Mocha test_command passed having tested nothing. These cases
# pin that a failing runner fails the job whatever it prints.
set -euo pipefail
cd "$(dirname "$0")/../.."

extract() {
  SELFTEST_STEP="$1" python3 - <<'PY'
import os, yaml
steps = yaml.safe_load(open('.github/workflows/contracts-test.yml'))['jobs']['test']['steps']
step = next(s for s in steps if s.get('name') == os.environ['SELFTEST_STEP'])
assert '${{' not in step['run'], 'run body must read env vars only'
print(step['run'])
PY
}

RUN=$(extract 'Run contract tests')
VERDICT=$(extract 'Check test results')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# run_ <name> <expected status> <test_command>; bash -e as the runner's default shell
run_() {
  : > "$tmp/out"
  ( cd "$tmp" && env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" TEST_COMMAND="$3" PACKAGE_MANAGER=npm \
      bash -e -c "$RUN" >/dev/null 2>&1 ) || true
  local got
  got=$(sed -n 's/^status=//p' "$tmp/out")
  if [ "$got" = "$2" ]; then echo "ok   run: $1"; else echo "FAIL run: $1 (status=$got, want $2)"; fails=$((fails+1)); fi
}

# verdict_ <name> <pass|fail> KEY=VALUE...
verdict_() {
  local name=$1 expect=$2 rc=0 got=pass; shift 2
  env -i PATH="$PATH" "$@" bash -e -c "$VERDICT" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || got=fail
  if [ "$got" = "$expect" ]; then echo "ok   verdict: $name"; else echo "FAIL verdict: $name (got $got)"; fails=$((fails+1)); fi
}

run_ 'passing runner records 0'                   0 'echo "3 passing"'
run_ 'crash with no Mocha line records its code'  3 'echo "Error HH600: Compilation failed"; exit 3'
run_ 'non-Mocha runner failing records its code'  1 'echo "[FAIL] testTransfer()"; exit 1'
run_ 'exit code survives the tee'                 2 'exit 2'

verdict_ 'green run'                     pass STATUS=0 FAILED=0
verdict_ 'runner failed, nothing parsed' fail STATUS=3 FAILED=0
verdict_ 'no status reported'            fail STATUS='' FAILED=0
verdict_ 'Mocha counted failures'        fail STATUS=0 FAILED=2
verdict_ 'no Mocha tally, runner green'  pass STATUS=0 FAILED=''

echo "$fails failing case(s)"; exit $((fails > 0))

#!/usr/bin/env bash
# Executes react-test.yml's "Parse test results" and "Check test results"
# scripts verbatim against a table of logs and exit codes. Both are extracted
# from the workflow rather than copied, so the test cannot drift from what
# consumers run.
#
# This is the gate that used to pass having measured nothing: the test step
# discarded its exit code with `|| true` and the verdict came from grepping
# Jest's exact wording out of the log, so any other reporter parsed as zero
# tests and zero failures. The cases below pin both halves -- a runner that
# fails must fail the job whatever it prints, and a non-Jest reporter must
# still be counted.
set -euo pipefail
cd "$(dirname "$0")/../.."

extract() {
  SELFTEST_STEP="$1" python3 - <<'PY'
import os, yaml
wf = yaml.safe_load(open('.github/workflows/react-test.yml'))
steps = wf['jobs']['test']['steps']
name = os.environ['SELFTEST_STEP']
step = next(s for s in steps if s.get('name') == name)
body = step['run']
assert '${{' not in body, f'{name}: run body must read env vars only'
print(body)
PY
}

PARSE=$(extract 'Parse test results')
VERDICT=$(extract 'Check test results')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# parse_ <name> <expected passed> <expected failed> <log text>
parse_() {
  local name=$1 want_passed=$2 want_failed=$3 log=$4
  printf '%s\n' "$log" > "$tmp/test-output.log"
  : > "$tmp/out"
  local rc=0
  ( cd "$tmp" && env -i PATH="$PATH" STATUS=0 \
      GITHUB_OUTPUT="$tmp/out" GITHUB_STEP_SUMMARY=/dev/null \
      bash -eo pipefail -c "$PARSE" >/dev/null 2>&1 ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL parse: $name (the step itself exited $rc)"
    fails=$((fails+1))
    return
  fi
  local got_passed got_failed
  got_passed=$(grep -oE '^passed=.*' "$tmp/out" | tail -1 | cut -d= -f2)
  got_failed=$(grep -oE '^failed=.*' "$tmp/out" | tail -1 | cut -d= -f2)
  if [ "$got_passed" = "$want_passed" ] && [ "$got_failed" = "$want_failed" ]; then
    echo "ok   parse: $name"
  else
    echo "FAIL parse: $name (passed=$got_passed/$want_passed failed=$got_failed/$want_failed)"
    fails=$((fails+1))
  fi
}

# verdict_ <name> <expected: pass|fail> KEY=VALUE...
verdict_() {
  local name=$1 expect=$2; shift 2
  local rc=0
  env -i PATH="$PATH" GITHUB_STEP_SUMMARY=/dev/null "$@" \
      bash -eo pipefail -c "$VERDICT" >/dev/null 2>&1 || rc=$?
  local got=pass; [ "$rc" -eq 0 ] || got=fail
  if [ "$got" = "$expect" ]; then echo "ok   verdict: $name"
  else echo "FAIL verdict: $name (expected $expect, got $got)"; fails=$((fails+1)); fi
}

# --- parsing: the reporter's wording must not decide the count ---
parse_ 'jest passed'        5   0 'Tests:       5 passed, 5 total'
parse_ 'jest with failures' 3   2 'Tests:       2 failed, 3 passed, 5 total'
parse_ 'rstest passed'      152 0 ' Tests 152 passed'
parse_ 'vitest with failures' 150 2 ' Tests  2 failed | 150 passed (152)'
parse_ 'silent reporter'    unknown 0 'Done in 1.84s'
# A monorepo task runner prints one tally per package. Taking the last of them
# reported 16 of this repository's 408 tests and called it the total.
parse_ 'monorepo sums packages' 408 0 'design-system:test:       Tests 94 passed
mf-shared-config:test:       Tests 3 passed
shell-auth-context:test:       Tests 36 passed
mock-api:test:       Tests 107 passed
shell:test:       Tests 152 passed
tofugen:test:       Tests 16 passed'
parse_ 'monorepo sums failures' 246 4 'a:test:       Tests 2 failed | 94 passed
b:test:       Tests 2 failed | 152 passed'
# "Test Files" counts files, not tests, and must not be mistaken for a tally.
parse_ 'test files line ignored' 152 0 ' Test Files 28 passed
 Tests 152 passed'

# --- the verdict: the runner's exit code decides ---
verdict_ 'exit 0, no failures'            pass STATUS=0 FAILED=0
verdict_ 'exit 0, unparseable count'      pass STATUS=0 FAILED=unknown
verdict_ 'exit 1 fails'                   fail STATUS=1 FAILED=0
# The old gate passed this one: a crashed runner prints nothing Jest-shaped,
# so the parse found no failures and nothing else was consulted.
verdict_ 'exit 1 with unparseable count'  fail STATUS=1 FAILED=unknown
verdict_ 'exit 0 but failures counted'    fail STATUS=0 FAILED=3
# A missing exit code means the test step never ran its last line.
verdict_ 'absent status fails'            fail STATUS= FAILED=0

echo "$fails failing case(s)"
exit $((fails > 0))

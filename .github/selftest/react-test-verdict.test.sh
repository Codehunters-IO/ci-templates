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
RUNTESTS=$(extract 'Run tests')
RESOLVE=$(extract 'Resolve package manager')
COVGATE=$(extract 'Check coverage threshold')

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

# --- colour: what the runner actually prints on a runner ---
# GitHub sets CI=true and picocolors (rstest, vitest) emits SGR escapes on that
# alone, with no TTY check. Every case above is plain text, so the parser was
# green here and reported `unknown` for all of these in CI -- the same "gate
# measured nothing" defect this file exists to prevent, one layer down. \033
# is written as a real ESC byte via printf %b.
ansi() { printf '%b' "$1"; }
parse_ 'ansi jest passed'     5   0 "$(ansi '\033[1mTests:\033[22m  \033[32m5 passed\033[39m, 5 total')"
parse_ 'ansi jest failures'   3   2 "$(ansi '\033[1mTests:\033[22m \033[31m2 failed\033[39m, \033[32m3 passed\033[39m, 5 total')"
parse_ 'ansi rstest'          150 0 "$(ansi '\033[2mTests\033[22m  150 passed (150)')"
parse_ 'ansi turbo prefix'    152 0 "$(ansi '\033[36mshell:test:\033[0m \033[1mTests:\033[22m 152 passed')"
parse_ 'ansi inside count'    5   0 "$(ansi 'Tests:  \033[32m5\033[39m passed, 5 total')"

# --- a test name must not be read as a tally ---
# describe('retry tests') + it('gives up after 3 failed attempts') put both
# "tests" and "3 failed" on one line, and an unanchored match called a green
# run three failures.
parse_ 'test name not a tally' 152 0 'shell:test:    ok src/retry.test.ts > retry tests > gives up after 3 failed attempts  4ms
shell:test:       Tests 152 passed'
parse_ 'thousands separator'  1234 0 'Tests:  1,234 passed, 1,234 total'

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

# --- the exit code must survive a failing runner ---
# Production runs these bodies under `bash -e {0}` (no `shell:` key, so no
# pipefail and no -u unless the body sets it). `set -uo pipefail` does not
# clear that -e, so before the `set +e` a failing runner aborted the step at
# the pipeline and `status` was never written: the gate then reported an
# ordinary test failure as "did not report an exit code". Driven with -e only,
# to match the runner rather than the stricter shell used above.
runstep_() {
  local name=$1 runner_rc=$2 want=$3
  cat > "$tmp/fakepm" <<EOF
#!/usr/bin/env bash
printf 'Tests: 2 failed, 3 passed, 5 total\n'
exit $runner_rc
EOF
  chmod +x "$tmp/fakepm"
  : > "$tmp/out"
  ( cd "$tmp" && env -i PATH="$PATH" PM_RUN="$tmp/fakepm" ARGS_SEP= \
      TEST_COMMAND=test TEST_ARGS= \
      GITHUB_OUTPUT="$tmp/out" bash -e -c "$RUNTESTS" >/dev/null 2>&1 ) || true
  local got
  got=$(grep -oE '^status=.*' "$tmp/out" | tail -1 | cut -d= -f2 || true)
  if [ "${got:-none}" = "$want" ]; then echo "ok   runstep: $name"
  else echo "FAIL runstep: $name (status=${got:-none}, wanted $want)"; fails=$((fails+1)); fi
}
runstep_ 'passing runner records 0' 0 0
runstep_ 'failing runner records its code' 1 1

# --- npm needs the -- separator or test_args is silently dropped ---
# `npm run test --coverage` reaches the script with an empty argv; npm parses
# the flags as its own. yarn and pnpm forward positionally and must not get one.
sep_() {
  local pm=$1 want=$2
  : > "$tmp/out"
  env -i PATH="$PATH" PM="$pm" GITHUB_OUTPUT="$tmp/out" \
      bash -e -c "$RESOLVE" >/dev/null 2>&1 || true
  local got
  got=$(grep -oE '^args_sep=.*' "$tmp/out" | tail -1 | cut -d= -f2- || true)
  if [ "${got-unset}" = "$want" ]; then echo "ok   args_sep: $pm"
  else echo "FAIL args_sep: $pm (got '${got-unset}', wanted '$want')"; fails=$((fails+1)); fi
}
sep_ npm  '--'
sep_ yarn ''
sep_ pnpm ''

# --- the coverage gate must not pass on a non-numeric percentage ---
# `bc` prints nothing for a non-number, `[ "" -eq 1 ]` then errors, and a
# failing condition inside `if` is exempt from -e: the gate passed.
covgate_() {
  local name=$1 expect=$2 coverage=$3 threshold=$4
  local rc=0
  env -i PATH="$PATH" COVERAGE="$coverage" THRESHOLD="$threshold" \
      bash -e -c "$COVGATE" >/dev/null 2>&1 || rc=$?
  local got=pass; [ "$rc" -eq 0 ] || got=fail
  if [ "$got" = "$expect" ]; then echo "ok   covgate: $name"
  else echo "FAIL covgate: $name (expected $expect, got $got)"; fails=$((fails+1)); fi
}
covgate_ 'above threshold'      pass 91.3 80
covgate_ 'below threshold'      fail 79.9 80
covgate_ 'non-numeric coverage' fail '[]'  80
covgate_ 'NaN coverage'         fail NaN   80
covgate_ 'non-numeric threshold' fail 91.3 'eighty'

# --- the gate must be wired to the real step outputs ---
# Every verdict case above supplies STATUS and FAILED by hand, so the env:
# block could be hardcoded, or point at the wrong step, and the suite would
# stay green while the gate went blind. `'${{' not in body` covers the script
# body only, never the env: block that feeds it.
if python3 - <<'PY'
import sys, yaml
wf = yaml.safe_load(open('.github/workflows/react-test.yml'))
steps = wf['jobs']['test']['steps']
def env_of(name):
    return next(s for s in steps if s.get('name') == name).get('env', {})
want = {
    'Check test results': {
        'STATUS': '${{ steps.test-run.outputs.status }}',
        'FAILED': '${{ steps.test-summary.outputs.failed }}',
    },
    'Run tests': {
        'PM_RUN': '${{ steps.pm.outputs.run }}',
        'ARGS_SEP': '${{ steps.pm.outputs.args_sep }}',
        'TEST_COMMAND': '${{ inputs.test_command }}',
        'TEST_ARGS': '${{ inputs.test_args }}',
    },
    'Check coverage threshold': {
        'COVERAGE': '${{ steps.coverage.outputs.percentage }}',
        'THRESHOLD': '${{ inputs.coverage_line_threshold }}',
    },
}
bad = []
for step, pairs in want.items():
    got = env_of(step)
    for key, expr in pairs.items():
        if got.get(key) != expr:
            bad.append(f'{step}.env.{key} is {got.get(key)!r}, expected {expr!r}')
if bad:
    print('\n'.join(bad), file=sys.stderr)
    sys.exit(1)
PY
then echo "ok   wiring: steps read the real outputs"
else echo "FAIL wiring: steps do not read the real outputs"; fails=$((fails+1)); fi

echo "$fails failing case(s)"
exit $((fails > 0))

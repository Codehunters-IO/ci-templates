#!/usr/bin/env bash
# Runs the deploy scripts of react-deploy-s3.yml and react-deploy-amplify.yml,
# extracted verbatim, against a fake aws CLI that records every call.
#
# Amplify used to call `aws amplify wait`, which the CLI does not have, and read
# the job status while it was still PENDING: every deploy failed. S3 used one
# `sync --delete`, which removed the chunks open tabs still load and could put
# index.html up before its assets. These cases pin the polling, the upload
# guard, the pass order, the cache headers and what the prune may delete.
set -euo pipefail
cd "$(dirname "$0")/../.."

extract() {
  python3 - "$1" "$2" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(f'.github/workflows/{sys.argv[1]}.yml'))['jobs']['deploy']['steps']
step = next(s for s in steps if s.get('name') == sys.argv[2])
assert '${{' not in step['run'], 'run body must read env vars only'
print(step['run'])
PY
}
S3=$(extract react-deploy-s3 'Deploy to S3')
AMPLIFY=$(extract react-deploy-amplify 'Deploy to Amplify')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
BIN="$tmp/bin"; mkdir -p "$BIN"
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

cat > "$BIN/aws" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$1 $2" in
  's3api list-objects-v2')
    case "$*" in *'--prefix static/'*) echo '["static/js/main.old.js","static/js/main.abc.js"]' ;; *) echo '[]' ;; esac ;;
  'cloudfront create-invalidation') echo I123 ;;
  'amplify create-deployment') echo '{"jobId":"7","zipUploadUrl":"https://upload.example/zip"}' ;;
  'amplify get-job') s=$(head -1 "$FAKE/statuses"); [ "$(wc -l < "$FAKE/statuses")" -gt 1 ] && sed -i.bak 1d "$FAKE/statuses"; echo "$s" ;;
esac
exit 0
SH
cat > "$BIN/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$FAKE/calls"
exit "${FAKE_CURL_RC:-0}"
SH
chmod +x "$BIN"/*

build() {
  rm -rf "$tmp/site" && mkdir -p "$tmp/site/build/static/js"
  touch "$tmp/site/build/index.html" "$tmp/site/build/favicon.ico" "$tmp/site/build/static/js/main.abc.js"
}

# s3 <immutable_paths>
s3() {
  build; : > "$tmp/calls"; : > "$tmp/out"
  ( cd "$tmp/site" && env -i PATH="$BIN:$PATH" FAKE="$tmp" GITHUB_OUTPUT="$tmp/out" GITHUB_STEP_SUMMARY=/dev/null \
      BUILD_OUTPUT_DIR=build S3_BUCKET=bucket CLOUDFRONT_DISTRIBUTION_ID=E1 \
      IMMUTABLE_PATHS="$1" ASSET_RETENTION_DAYS=7 WAIT_FOR_INVALIDATION=true \
      bash -e -c "$S3" >/dev/null 2>&1 ) && echo 0 || echo $?
}
# `|| true`: no match must report a FAIL below, not end the script under pipefail.
line_of() { { grep -nF -- "$1" "$tmp/calls" || true; } | head -1 | cut -d: -f1; }

rc=$(s3 'static/, assets/')
p1=$(line_of "--include static/*"); p2=$(line_of "--cache-control no-cache")
[ "$rc" = 0 ] && [ -n "$p1" ] && [ -n "$p2" ] && [ "$p1" -lt "$p2" ] \
  && ok 's3: hashed assets go up before the entry points' || fail "s3: pass order (rc=$rc p1=$p1 p2=$p2)"
grep -F -- '--include static/*' "$tmp/calls" | grep -qF 'immutable' \
  && ! grep -F -- '--include static/*' "$tmp/calls" | grep -qF -- '--delete' \
  && ok 's3: assets immutable and never --delete' || fail 's3: asset pass headers'
grep -F -- 'no-cache' "$tmp/calls" | grep -qF -- '--exclude static/*' \
  && grep -F -- 'no-cache' "$tmp/calls" | grep -qF -- '--delete' \
  && ok 's3: entry pass revalidates and deletes outside the asset prefixes' || fail 's3: entry pass flags'
grep -qF 's3 rm s3://bucket/static/js/main.old.js' "$tmp/calls" \
  && ! grep -qF 's3 rm s3://bucket/static/js/main.abc.js' "$tmp/calls" \
  && ok 's3: prune removes an old asset absent from the build, keeps the current one' || fail 's3: prune'
grep -qF 'cloudfront wait invalidation-completed --distribution-id E1 --id I123' "$tmp/calls" \
  && ok 's3: waits for the invalidation' || fail 's3: invalidation wait'

rc=$(s3 '')
[ "$rc" = 0 ] && ! grep -qF -- '--include' "$tmp/calls" && ! grep -qF 's3api' "$tmp/calls" \
  && ok 's3: no immutable paths -> one revalidated pass, no prune' || fail "s3: empty immutable_paths (rc=$rc)"

# amplify <curl rc> <timeout> <status...>
amplify() {
  local curl_rc=$1 timeout=$2; shift 2
  build; : > "$tmp/calls"; : > "$tmp/out"; printf '%s\n' "$@" > "$tmp/statuses"
  ( cd "$tmp/site" && env -i PATH="$BIN:$PATH" FAKE="$tmp" FAKE_CURL_RC="$curl_rc" \
      GITHUB_OUTPUT="$tmp/out" GITHUB_STEP_SUMMARY=/dev/null BUILD_OUTPUT_DIR=build ENVIRONMENT=test \
      AMPLIFY_APP_ID=app AMPLIFY_BRANCH=main AMPLIFY_TIMEOUT="$timeout" AMPLIFY_POLL_SECONDS=0 \
      bash -e -c "$AMPLIFY" >/dev/null 2>&1 ) && echo 0 || echo $?
}
status() { sed -n 's/^status=//p' "$tmp/out" | tail -1; }

rc=$(amplify 0 60 PENDING RUNNING SUCCEED)
[ "$rc" = 0 ] && [ "$(status)" = success ] && [ "$(grep -c 'amplify get-job' "$tmp/calls")" = 3 ] \
  && ok 'amplify: polls through PENDING and RUNNING to SUCCEED' || fail "amplify: success path (rc=$rc status=$(status))"
rc=$(amplify 0 60 RUNNING FAILED)
[ "$rc" != 0 ] && [ "$(status)" = failed ] && ok 'amplify: FAILED fails the job' || fail "amplify: FAILED (rc=$rc)"
rc=$(amplify 22 60 SUCCEED)
[ "$rc" != 0 ] && ! grep -qF 'amplify start-deployment' "$tmp/calls" \
  && grep -qF -- '--fail' "$tmp/calls" \
  && ok 'amplify: failed upload never starts the deployment' || fail "amplify: upload guard (rc=$rc)"
rc=$(amplify 0 0 RUNNING)
[ "$rc" != 0 ] && [ "$(status)" = timeout ] && ok 'amplify: still running at the deadline -> timeout' || fail "amplify: timeout (rc=$rc status=$(status))"

echo "$fails failing case(s)"; exit $((fails > 0))

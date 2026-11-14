#!/usr/bin/env bash
# Runs shared-gitops-promote.yml's two working steps, extracted verbatim:
#   "Set the image in the overlay" against fixture values files (needs yq, which
#   GitHub's ubuntu runners ship; skipped locally without it, fatal in CI);
#   "Commit or propose" against a local bare repository and a fake gh.
# Pins: only the three image keys change and comments survive; bad input is
# refused; dev commits to the default branch, other environments open a PR,
# and an unchanged digest promotes nothing.
set -euo pipefail
cd "$(dirname "$0")/../.."

extract() {
  python3 - "$1" <<'PY'
import sys, yaml
steps = yaml.safe_load(open('.github/workflows/shared-gitops-promote.yml'))['jobs']['promote']['steps']
step = next(s for s in steps if s.get('name') == sys.argv[1])
assert '${{' not in step['run'], 'run body must read env vars only'
print(step['run'])
PY
}
SET=$(extract 'Set the image in the overlay')
COMMIT=$(extract 'Commit or propose')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
DIGEST="sha256:$(printf 'b%.0s' $(seq 64))"
URI='123.dkr.ecr.us-east-1.amazonaws.com/orders:1a2b3c4'

overlay() {
  mkdir -p "$1/apps/orders/overlays/dev"
  cat > "$1/apps/orders/overlays/dev/values.yaml" <<'YAML'
# Dev overrides. Auto-sync + selfHeal.
springProfile: dev

image:
  tag: dev-latest   # replaced by promotion

replicaCount: 1
YAML
}

# ---- Set the image in the overlay -------------------------------------------
if command -v yq >/dev/null; then
  set_() {  # set_ <dir> <service> <env> <digest>; prints the exit code
    ( cd "$1" && env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/out" SERVICE="$2" ENVIRONMENT="$3" \
        IMAGE_URI="$URI" IMAGE_DIGEST="$4" bash -e -c "$SET" >/dev/null 2>&1 ) && echo 0 || echo $?
  }
  # A git repository, as the checkout is: the step ends by showing `git diff`.
  d="$tmp/set"; overlay "$d"; git init -q "$d"; : > "$tmp/out"
  rc=$(set_ "$d" orders dev "$DIGEST"); f="$d/apps/orders/overlays/dev/values.yaml"
  [ "$rc" = 0 ] \
    && [ "$(yq '.image.repository' "$f")" = '123.dkr.ecr.us-east-1.amazonaws.com/orders' ] \
    && [ "$(yq '.image.tag' "$f")" = '1a2b3c4' ] && [ "$(yq '.image.digest' "$f")" = "$DIGEST" ] \
    && ok 'set: repository, tag and digest written' || fail "set: image keys (rc=$rc)"
  grep -q '^# Dev overrides' "$f" && grep -q 'replaced by promotion' "$f" \
    && [ "$(yq '.replicaCount' "$f")" = 1 ] && [ "$(yq '.springProfile' "$f")" = dev ] \
    && ok 'set: comments and other keys survive' || fail 'set: collateral edits'
  [ "$(set_ "$d" orders dev 'latest')" != 0 ] && ok 'set: a non-digest is refused' || fail 'set: bad digest accepted'
  [ "$(set_ "$d" orders stg "$DIGEST")" != 0 ] && ok 'set: a missing overlay is refused' || fail 'set: missing overlay accepted'
  [ "$(set_ "$d" '../x' dev "$DIGEST")" != 0 ] && ok 'set: a path in the service name is refused' || fail 'set: traversal accepted'
  printf 'replicaCount: 1\n' > "$f"
  [ "$(set_ "$d" orders dev "$DIGEST")" != 0 ] && ok 'set: an overlay without image: is refused' || fail 'set: no image block accepted'
elif [ "${CI:-}" = true ]; then
  fail 'yq is missing on the runner'
else
  echo 'skip set: yq not installed (runs in CI)'
fi

# ---- Commit or propose ------------------------------------------------------
BIN="$tmp/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_GH_LOG"
case "$1 $2" in
  'pr list') echo '' ;;
  'pr create') echo 'https://github.com/o/gitops/pull/9' ;;
esac
SH
chmod +x "$BIN/gh"

origin="$tmp/origin.git"; git init -q --bare -b main "$origin"
seed="$tmp/seed"; git init -q -b main "$seed"; overlay "$seed"
git -C "$seed" -c user.name=t -c user.email=t@t add . && git -C "$seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$seed" push -q "$origin" main

# commit_ <env> <edit: yes|no>; clones, optionally edits the overlay, runs the step
commit_() {
  local w="$tmp/w-$1-$RANDOM"; git clone -q "$origin" "$w"
  # Per-environment value: each case must see a change against what the previous one pushed.
  [ "$2" = yes ] && sed -i.bak "s/^  tag: .*/  tag: $1-1a2b3c4/" "$w/apps/orders/overlays/dev/values.yaml" && rm -f "$w"/apps/orders/overlays/dev/*.bak
  : > "$tmp/out"; : > "$tmp/gh.log"
  ( cd "$w" && env -i PATH="$BIN:$PATH" HOME="$tmp" GITHUB_OUTPUT="$tmp/out" FAKE_GH_LOG="$tmp/gh.log" GH_TOKEN=x \
      FILE=apps/orders/overlays/dev/values.yaml SERVICE=orders SHORT=bbbbbbbbbbbb ENVIRONMENT="$1" \
      IMAGE_URI="$URI" IMAGE_DIGEST="$DIGEST" DIRECT='dev, sandbox' SOURCE=https://ci/run \
      bash -e -c "$COMMIT" >/dev/null 2>&1 ) && echo 0 || echo $?
}
promoted() { sed -n 's/^promoted=//p' "$tmp/out"; }

rc=$(commit_ dev no)
[ "$rc" = 0 ] && [ "$(promoted)" = false ] && ok 'commit: unchanged values promote nothing' || fail "commit: no-op (rc=$rc)"

before=$(git -C "$origin" rev-parse main)
rc=$(commit_ dev yes)
[ "$rc" = 0 ] && [ "$(promoted)" = true ] && [ "$(git -C "$origin" rev-parse main)" != "$before" ] \
  && git -C "$origin" log -1 --format=%B main | grep -qF "Digest: $DIGEST" && [ ! -s "$tmp/gh.log" ] \
  && ok 'commit: a direct environment lands on main with the digest in the message' || fail "commit: direct (rc=$rc)"

before=$(git -C "$origin" rev-parse main)
rc=$(commit_ prod yes)
[ "$rc" = 0 ] && [ "$(git -C "$origin" rev-parse main)" = "$before" ] \
  && git -C "$origin" rev-parse -q --verify refs/heads/promote/orders-prod-bbbbbbbbbbbb >/dev/null \
  && grep -q '^gh pr create' "$tmp/gh.log" && grep -q '^pull_request_url=https://github.com/o/gitops/pull/9' "$tmp/out" \
  && ok 'commit: any other environment opens a PR and leaves main alone' || fail "commit: PR path (rc=$rc)"

echo "$fails failing case(s)"; exit $((fails > 0))

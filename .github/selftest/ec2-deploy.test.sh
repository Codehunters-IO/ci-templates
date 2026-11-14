#!/usr/bin/env bash
# deploy.sh is the part of the EC2 deploys that touches a running service, and
# nothing else here executes it: a wrong branch only shows up on a real host,
# as an outage. This extracts it from both workflows, asserts the two copies are
# identical, and runs it against a fake docker whose images are healthy or not
# by name. Pins: health check gates success, a failed one restores the previous
# compose file and exits 42, and image cleanup spares the previous image.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

extract() {
  awk "/<< 'DEPLOY_SCRIPT'/{f=1;next} /^          DEPLOY_SCRIPT\$/{f=0} f" \
    ".github/workflows/$1.yml" | sed 's/^          //'
}
extract shared-deploy-ec2 > "$WORK/deploy.sh"
extract shared-deploy-ec2-vpn > "$WORK/deploy-vpn.sh"
chmod +x "$WORK/deploy.sh"

fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

[ -s "$WORK/deploy.sh" ] && cmp -s "$WORK/deploy.sh" "$WORK/deploy-vpn.sh" \
  && ok 'ec2 and ec2-vpn carry the same deploy.sh' || fail 'ec2 and ec2-vpn carry the same deploy.sh'

# Fake host. STATE/running holds the image the container runs; an image whose
# name contains "bad" never answers its health path and exits.
BIN="$WORK/bin"; STATE="$WORK/state"; mkdir -p "$BIN" "$STATE"
cat > "$BIN/docker" <<'SH'
#!/usr/bin/env bash
S="$FAKE_STATE"; running() { cat "$S/running" 2>/dev/null; }
case "$1" in
  volume|login) exit 0 ;;
  pull) echo "$2" >> "$S/pulled"; exit 0 ;;
  ps) [ -s "$S/running" ] && echo cid; exit 0 ;;
  kill|rm) : > "$S/running"; exit 0 ;;
  logs) exit 0 ;;
  rmi) shift; for a in "$@"; do [ "$a" = -f ] || echo "$a" >> "$S/removed"; done; exit 0 ;;
  images) sort -u "$S/pulled" | sed 's/^/id:/'; exit 0 ;;
  image) echo "id:${!#}"; exit 0 ;;
  inspect)
    img=$(running); [ -n "$img" ] || exit 1
    case "$3" in
      *Config.Image*) echo "$img" ;;
      *) case "$img" in *bad*) echo 'exited|0|' ;; *) echo 'running|0|' ;; esac ;;
    esac ;;
  compose)
    file=$(sed -n 's/.*-f \([^ ]*\).*/\1/p' <<< "$*")
    case "$*" in
      *' up '*) sed -n 's/^    image: //p' "$file" > "$S/running" ;;
      *' down'*) : > "$S/running" ;;
    esac ;;
esac
SH
cat > "$BIN/curl" <<'SH'
#!/usr/bin/env bash
case "$(cat "$FAKE_STATE/running" 2>/dev/null)" in ''|*bad*) exit 7 ;; *) exit 0 ;; esac
SH
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$BIN/sudo"
printf '#!/usr/bin/env bash\nshift; exec "$@"\n' > "$BIN/timeout"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/aws"
chmod +x "$BIN"/*

deploy() {
  PATH="$BIN:$PATH" FAKE_STATE="$STATE" DEPLOY_DIR="$WORK/app" \
  REPO_NAME=app IMAGE_TAG="$1" IMAGE_REF="ecr.example/app:$1" AWS_ECR_URL=ecr.example \
  AWS_REGION=us-east-1 APP_PORT=8080 ENVIRONMENT=test DOCKER_PLATFORM=linux/amd64 \
  MEMORY_LIMIT=512m MEMORY_RESERVATION=256m INTERNAL_PORT=8080 \
  CONTAINER_ENV_VARS_B64= EXTRA_VOLUMES_B64= HEALTH_CHECK_PATH="${2-/health}" HEALTH_CHECK_TIMEOUT=10 \
  "$WORK/deploy.sh" > "$WORK/log" 2>&1 && echo 0 || echo $?
}
running() { cat "$STATE/running"; }
compose_image() { sed -n 's/^    image: //p' "$WORK/app/docker-compose.yml"; }

rc=$(deploy bad1)
[ "$rc" = 42 ] && grep -q 'nothing to roll back' "$WORK/log" \
  && ok 'first deploy unhealthy -> 42, nothing to roll back to' || fail "first deploy unhealthy -> 42 (got $rc)"

rc=$(deploy v1)
[ "$rc" = 0 ] && [ "$(running)" = ecr.example/app:v1 ] \
  && ok 'first deploy healthy -> 0' || fail "first deploy healthy -> 0 (got $rc)"

rc=$(deploy v2)
[ "$rc" = 0 ] && [ "$(running)" = ecr.example/app:v2 ] && [ "$(compose_image)" = ecr.example/app:v2 ] \
  && ok 'upgrade healthy -> 0, compose on v2' || fail "upgrade healthy -> 0 (got $rc)"

rc=$(deploy bad3)
[ "$rc" = 42 ] && [ "$(running)" = ecr.example/app:v2 ] && [ "$(compose_image)" = ecr.example/app:v2 ] \
  && grep -q 'Rolled back' "$WORK/log" \
  && ok 'upgrade unhealthy -> 42, v2 serving again from its compose' || fail "upgrade unhealthy -> rollback (got $rc, running $(running))"

rc=$(deploy bad4 '')
[ "$rc" = 42 ] && [ "$(running)" = ecr.example/app:v2 ] \
  && ok 'no health path: exited container -> 42, rolled back' || fail "no health path rollback (got $rc)"

: > "$STATE/removed"
rc=$(deploy v5)
[ "$rc" = 0 ] && grep -qx 'id:ecr.example/app:v1' "$STATE/removed" \
  && ! grep -qx 'id:ecr.example/app:v2' "$STATE/removed" \
  && ! grep -qx 'id:ecr.example/app:v5' "$STATE/removed" \
  && ok 'cleanup removes v1, keeps the previous v2 and the new v5' || fail "cleanup (got $rc; removed: $(tr '\n' ' ' < "$STATE/removed"))"

echo "$fails failing case(s)"; exit $((fails > 0))

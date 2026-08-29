#!/usr/bin/env bash
#
# ssh-deploy-debug.sh — reproduce the EC2 SSH deploy stages locally to isolate a
# "Process completed with exit code 1" failure from shared-deploy-ec2[-vpn].yml.
#
# It SSHes into the target host and runs each deploy stage SEPARATELY (ECR login,
# image pull, docker network/volume presence, optional compose up), reporting
# PASS/FAIL per stage instead of aborting on the first error. The stage that FAILs
# is the root cause of the pipeline's exit 1.
#
# It does NOT modify the workflow and only runs read-mostly checks by default
# (compose up is opt-in with --up).
#
# Requirements (local): ssh, ssh-keyscan. (remote host): docker, aws cli.
#
# Usage:
#   scripts/ssh-deploy-debug.sh \
#     --host <EC2_HOST> --user <EC2_USER> --key <path-to-pem> \
#     --ecr-url <AWS_ECR_URL> --region <AWS_REGION> --repo <REPO_NAME> \
#     [--tag <IMAGE_TAG>] [--access-key <ID>] [--secret-key <SECRET>] [--up]
#
# Values map 1:1 to the Environment secrets (AWS_EC2_HOST, AWS_EC2_USER,
# AWS_EC2_SSH_KEY, AWS_ECR_URL, AWS_REGION, etc.). For the VPN flow, bring up
# WireGuard first so <host> is reachable.
#
# All flags can also be supplied as env vars: HOST USER KEY ECR_URL REGION REPO TAG
# AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
#
set -uo pipefail

HOST="${HOST:-}"; USER_="${USER:-}"; KEY="${KEY:-}"
ECR_URL="${ECR_URL:-}"; REGION="${REGION:-}"; REPO="${REPO:-}"; TAG="${TAG:-latest}"
ACCESS_KEY="${AWS_ACCESS_KEY_ID:-}"; SECRET_KEY="${AWS_SECRET_ACCESS_KEY:-}"
RUN_UP=false

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host)       HOST="$2"; shift 2;;
    --user)       USER_="$2"; shift 2;;
    --key)        KEY="$2"; shift 2;;
    --ecr-url)    ECR_URL="$2"; shift 2;;
    --region)     REGION="$2"; shift 2;;
    --repo)       REPO="$2"; shift 2;;
    --tag)        TAG="$2"; shift 2;;
    --access-key) ACCESS_KEY="$2"; shift 2;;
    --secret-key) SECRET_KEY="$2"; shift 2;;
    --up)         RUN_UP=true; shift;;
    -h|--help)    sed -n '2,33p' "$0"; exit 0;;
    *)            die "unknown option: $1";;
  esac
done

for v in HOST USER_ KEY ECR_URL REGION REPO; do
  [ -n "${!v}" ] || die "missing required value: ${v/USER_/USER}"
done
[ -f "$KEY" ] || die "key file not found: $KEY"
chmod 400 "$KEY" 2>/dev/null || true

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30"
PASS=0; FAIL=0
stage() {
  local name="$1"; shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then printf '  PASS: %s\n' "$name"; PASS=$((PASS+1));
  else printf '  FAIL: %s (this is a likely root cause)\n' "$name"; FAIL=$((FAIL+1)); fi
}
rssh() { ssh $SSH_OPTS "${USER_}@${HOST}" "$@"; }

# 0. connectivity
printf 'Seeding known_hosts for %s ...\n' "$HOST"
ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
stage "SSH connectivity"        rssh "echo connected as \$(whoami) on \$(hostname)"
stage "docker available"        rssh "docker version --format '{{.Server.Version}}'"
stage "aws cli available"       rssh "aws --version"
stage "docker network codehunters_net exists" rssh "docker network inspect codehunters_net >/dev/null"
stage "docker volume shared_logs exists"   rssh "docker volume inspect shared_logs >/dev/null"

# ECR login — the #1 suspect when Environment AWS creds are invalid/rotated
ECR_CMD="aws ecr get-login-password --region ${REGION}"
[ -n "$ACCESS_KEY" ] && ECR_CMD="AWS_ACCESS_KEY_ID='${ACCESS_KEY}' AWS_SECRET_ACCESS_KEY='${SECRET_KEY}' ${ECR_CMD}"
stage "ECR login" rssh "${ECR_CMD} | docker login --username AWS --password-stdin ${ECR_URL}"

# Image pull (needs successful login above)
stage "docker pull ${REPO}:${TAG}" rssh "docker pull ${ECR_URL}/${REPO}:${TAG}"

if $RUN_UP; then
  stage "compose up (DESTRUCTIVE)" rssh "cd /opt/docker/${REPO} && ./start.sh"
fi

printf '\n----\nResult: %s passed, %s failed.\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'The first FAIL above is what makes the pipeline deploy step exit 1.\n'
  printf 'Most common: invalid/rotated Environment AWS creds (ECR login), missing image tag, or missing codehunters_net/shared_logs.\n'
  exit 1
fi
printf 'All stages passed — the SSH deploy should succeed.\n'

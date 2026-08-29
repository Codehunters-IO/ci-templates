#!/usr/bin/env bash
#
# clone-environments.sh — provision GitHub Actions Environments (cert, prod) for the
# codehunters microservices by cloning VARIABLES from an existing source environment (develop)
# and setting SECRETS from per-environment files.
#
# WHY a script: GitHub never exposes secret VALUES via API/CLI (write-only), so secrets
# cannot be truly "cloned" — only their values that YOU provide are set. Variables ARE
# readable, so they are cloned automatically from the source environment.
#
# SAFETY: cert/prod usually need DIFFERENT values than develop (other EC2 host, port,
# WireGuard peer, maybe another AWS account). This script NEVER copies develop's secret
# values into cert/prod. It sets secrets only from the per-env files you fill in.
#
# Requirements: gh (authenticated, repo admin), jq.
#
# Usage:
#   scripts/clone-environments.sh [options]
#
# Options:
#   --org NAME          GitHub org (default: Codehunters-IO)
#   --repos "a b c"     Space-separated repo names (default: the 5 codehunters microservices)
#   --src-env NAME      Source environment to clone variables from (default: develop)
#   --envs "cert prod"  Target environments to create/populate (default: cert prod)
#   --secrets-dir DIR   Directory with <repo>.<env>.env files (default: ./env-secrets)
#   --vars-only         Clone variables only; skip secrets entirely
#   --template          Only write secret-name templates per repo/env, then exit
#   --dry-run           Print actions without mutating anything
#   -h, --help          Show this help
#
# Per-env secret files (KEY=VALUE, one per line, '#' comments allowed):
#   <secrets-dir>/<repo>.<env>.env      e.g. env-secrets/codehunters-ms-auth.cert.env
# Generate the name templates first with --template, fill the values, then run for real.
#
set -euo pipefail

ORG="Codehunters-IO"
REPOS="codehunters-ms-auth codehunters-ms-payment codehunters-ms-file-share codehunters-ms-notifications codehunters-ms-raffles"
SRC_ENV="develop"
TARGET_ENVS="cert prod"
SECRETS_DIR="./env-secrets"
VARS_ONLY=false
TEMPLATE_ONLY=false
DRY_RUN=false

log()  { printf '%s\n' "$*"; }
run()  { if $DRY_RUN; then log "  [dry-run] $*"; else eval "$*"; fi; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --org)         ORG="$2"; shift 2;;
    --repos)       REPOS="$2"; shift 2;;
    --src-env)     SRC_ENV="$2"; shift 2;;
    --envs)        TARGET_ENVS="$2"; shift 2;;
    --secrets-dir) SECRETS_DIR="$2"; shift 2;;
    --vars-only)   VARS_ONLY=true; shift;;
    --template)    TEMPLATE_ONLY=true; shift;;
    --dry-run)     DRY_RUN=true; shift;;
    -h|--help)     sed -n '2,40p' "$0"; exit 0;;
    *)             die "unknown option: $1";;
  esac
done

command -v gh >/dev/null || die "gh CLI not found"
command -v jq >/dev/null || die "jq not found"
gh auth status >/dev/null 2>&1 || die "gh not authenticated (run: gh auth login)"

mkdir -p "$SECRETS_DIR"

create_env() {
  local repo="$1" env="$2"
  log "• [$repo] ensure environment '$env'"
  run "gh api -X PUT \"repos/$ORG/$repo/environments/$env\" >/dev/null"
}

clone_vars() {
  local repo="$1" env="$2" count=0
  log "• [$repo] clone variables $SRC_ENV -> $env"
  local pairs
  pairs="$(gh variable list -R "$ORG/$repo" --env "$SRC_ENV" --json name,value \
            -q '.[] | "\(.name)\t\(.value)"' 2>/dev/null || true)"
  if [ -z "$pairs" ]; then log "  (no variables in $SRC_ENV)"; return; fi
  while IFS=$'\t' read -r name value; do
    [ -z "$name" ] && continue
    run "gh variable set \"$name\" -R \"$ORG/$repo\" --env \"$env\" --body \"$value\""
    count=$((count+1))
  done <<< "$pairs"
  log "  $count variable(s)"
}

write_template() {
  local repo="$1" env="$2" file="$SECRETS_DIR/$repo.$env.env"
  if [ -f "$file" ]; then log "  template exists, keeping: $file"; return; fi
  local names
  names="$(gh secret list -R "$ORG/$repo" --env "$SRC_ENV" --json name -q '.[].name' 2>/dev/null || true)"
  [ -z "$names" ] && { log "  (no secrets in $SRC_ENV to template)"; return; }
  {
    echo "# Secrets for $repo / environment '$env'"
    echo "# Fill REAL values for THIS environment (do NOT reuse develop's values blindly)."
    echo "# Lines starting with # are ignored. Delete keys that are shared at org level."
    while IFS= read -r n; do [ -n "$n" ] && echo "$n="; done <<< "$names"
  } > "$file"
  log "  wrote template: $file"
}

set_secrets() {
  local repo="$1" env="$2" file="$SECRETS_DIR/$repo.$env.env" count=0
  if [ ! -f "$file" ]; then
    log "  ⚠ no secrets file ($file) — skipping secrets for $repo/$env (run with --template first)"
    return
  fi
  log "• [$repo] set secrets from $file -> $env"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"            # ltrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue;; esac
    local key="${line%%=*}" val="${line#*=}"
    [ -z "$key" ] && continue
    if [ -z "$val" ]; then log "  ⚠ empty value for $key — skipped"; continue; fi
    run "gh secret set \"$key\" -R \"$ORG/$repo\" --env \"$env\" --body \"$val\""
    count=$((count+1))
  done < "$file"
  log "  $count secret(s)"
}

log "Org=$ORG  src-env=$SRC_ENV  target-envs=[$TARGET_ENVS]  vars-only=$VARS_ONLY  template-only=$TEMPLATE_ONLY  dry-run=$DRY_RUN"
log "Repos: $REPOS"
log "----"

for repo in $REPOS; do
  for env in $TARGET_ENVS; do
    if $TEMPLATE_ONLY; then
      write_template "$repo" "$env"
      continue
    fi
    create_env "$repo" "$env"
    clone_vars "$repo" "$env"
    $VARS_ONLY || set_secrets "$repo" "$env"
  done
done

log "----"
if $TEMPLATE_ONLY; then
  log "Templates written under $SECRETS_DIR. Fill values, then re-run without --template."
else
  log "Done. Reminder: set required reviewers on the 'prod' environment, and add"
  log "$SECRETS_DIR/ to .gitignore (never commit filled secret files)."
fi

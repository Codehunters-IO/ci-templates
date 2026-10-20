#!/usr/bin/env bash
# scripts/workflow-graph.py reads `uses:` lines instead of parsing YAML, and
# scripts/new-pipeline.py reads each template's `# Copy to:` header. Both lean
# on layout conventions nothing else enforces, so a reformatted workflow or a
# renamed template breaks them quietly. These cases run against the real
# files, not fixtures: drift in the repository is exactly what they catch.
set -euo pipefail
cd "$(dirname "$0")/../.."

fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

TREE=$(python3 scripts/workflow-graph.py java-pr-pipeline.yml)
check 'graph follows a call into a second file' \
  'grep -qF "pipeline → java-pr-gates.yml" <<<"$TREE" && grep -qF "test → java-test.yml" <<<"$TREE"'

# Blank lines between jobs once reset the parser and pinned every edge on the first job.
MAIN=$(python3 scripts/workflow-graph.py java-main-pipeline.yml)
check 'graph keeps each job id after blank lines' \
  'grep -qF "deploy-eks → shared-deploy-eks.yml" <<<"$MAIN" && ! grep -qF "commit-lint → java-build.yml" <<<"$MAIN"'

# Every stack pipeline a template calls must show up as a root of the full tree.
ALL=$(python3 scripts/workflow-graph.py)
for p in $(grep -hoE 'ci-templates/\.github/workflows/[a-z-]+-pipeline\.yml' templates/*.yml | sort -u | sed 's#.*/##'); do
  check "graph lists $p as an entry point" 'grep -qx "$p" <<<"$ALL"'
done

check 'graph rejects an unknown workflow' '! python3 scripts/workflow-graph.py nope.yml 2>/dev/null'
check 'mermaid output starts a flowchart' '[ "$(python3 scripts/workflow-graph.py --mermaid | head -1)" = "flowchart LR" ]'

REPO=$(mktemp -d); trap 'rm -rf "$REPO"' EXIT
python3 scripts/new-pipeline.py java "$REPO" >/dev/null
check 'scaffold drops the stack prefix per Copy to header' \
  '[ -f "$REPO/.github/workflows/validate.yml" ] && [ -f "$REPO/.github/workflows/tag-deploy.yml" ]'
check 'scaffold replaces <org>' '! grep -rqF "<org>" "$REPO/.github/workflows"'
check 'scaffold refuses to overwrite' '! python3 scripts/new-pipeline.py java "$REPO" 2>/dev/null'
check 'scaffold keeps java-library out of java' '! grep -rqF "java-library" "$REPO/.github/workflows"'

C=$(mktemp -d); trap 'rm -rf "$REPO" "$C"' EXIT
python3 scripts/new-pipeline.py contracts "$C" >/dev/null
check 'scaffold leaves contracts-pr-full opt-in' '[ ! -f "$C/.github/workflows/pr-validation.yml" ]'
check 'scaffold makes shared ask for --only' '! python3 scripts/new-pipeline.py shared "$C" 2>/dev/null'

# Every template must say where it goes, or the scaffold falls back to guessing.
for t in templates/*.yml; do
  case "$t" in templates/shared-*) continue ;; esac
  check "$(basename "$t") has a Copy to header" 'grep -qE "^# Copy to: \.github/workflows/" "$t"'
done

echo "$fails failing case(s)"
exit $((fails > 0))

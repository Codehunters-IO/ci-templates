#!/usr/bin/env bash
# scripts/workflow-graph.py reads `uses:` lines instead of parsing YAML, and
# scripts/new-pipeline.py reads each template's `# Copy to:` header. Both lean
# on layout conventions nothing else enforces, so a reformatted workflow or a
# renamed template breaks them quietly. These cases run against the real
# files, not fixtures: drift in the repository is exactly what they catch.
set -euo pipefail
cd "$(dirname "$0")/../.."

fails=0
# check NAME COMMAND...: the command is run as given, never eval'd.
check() { local name=$1; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails+1)); fi; }
has()     { grep -qF -- "$2" <<<"$1"; }
lacks()   { ! grep -qF -- "$2" <<<"$1"; }
line_is() { grep -qxF -- "$2" <<<"$1"; }
refuses() { ! "$@" >/dev/null 2>&1; }
no_text() { ! grep -rqF -- "$1" "$2"; }

TREE=$(python3 scripts/workflow-graph.py java-pr-pipeline.yml)
check 'graph follows a call into a second file'  has "$TREE" 'pipeline → java-pr-gates.yml'
check 'graph descends into the called file'      has "$TREE" 'test → java-test.yml'

# Blank lines between jobs once reset the parser and pinned every edge on the first job.
MAIN=$(python3 scripts/workflow-graph.py java-main-pipeline.yml)
check 'graph keeps each job id after blank lines' has   "$MAIN" 'deploy-eks → shared-deploy-eks.yml'
check 'graph does not pin edges on the first job' lacks "$MAIN" 'commit-lint → java-build.yml'

# Every stack pipeline a template calls must show up as a root of the full tree.
ALL=$(python3 scripts/workflow-graph.py)
while read -r p; do
  check "graph lists $p as an entry point" line_is "$ALL" "$p"
done < <(grep -hoE 'ci-templates/\.github/workflows/[a-z-]+-pipeline\.yml' templates/*.yml | sort -u | sed 's#.*/##')

check 'graph rejects an unknown workflow' refuses python3 scripts/workflow-graph.py nope.yml
check 'mermaid output starts a flowchart' \
  line_is "$(python3 scripts/workflow-graph.py --mermaid | head -1)" 'flowchart LR'

REPO=$(mktemp -d); C=$(mktemp -d); trap 'rm -rf "$REPO" "$C"' EXIT
WF=$REPO/.github/workflows
python3 scripts/new-pipeline.py java "$REPO" >/dev/null
check 'scaffold names validate per Copy to header'   test -f "$WF/validate.yml"
check 'scaffold names tag-deploy per Copy to header' test -f "$WF/tag-deploy.yml"
check 'scaffold replaces <org>'                no_text '<org>' "$WF"
check 'scaffold keeps java-library out of java' no_text 'java-library' "$WF"
check 'scaffold refuses to overwrite'          refuses python3 scripts/new-pipeline.py java "$REPO"

python3 scripts/new-pipeline.py contracts "$C" >/dev/null
check 'scaffold leaves contracts-pr-full opt-in' test ! -f "$C/.github/workflows/pr-validation.yml"
check 'scaffold makes shared ask for --only'     refuses python3 scripts/new-pipeline.py shared "$C"

# Every template must say where it goes, or the scaffold falls back to guessing.
for t in templates/*.yml; do
  case "$t" in templates/shared-*) continue ;; esac
  check "$(basename "$t") has a Copy to header" grep -qE '^# Copy to: \.github/workflows/' "$t"
done

echo "$fails failing case(s)"
exit $((fails > 0))

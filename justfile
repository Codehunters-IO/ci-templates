# Terminal entry points for working on this repository without an editor.
# `just` with no arguments lists them. Needs python3 and actionlint; zizmor and
# act only for the recipes that name them.

workflows := ".github/workflows"

default:
    @just --list

# actionlint with the flags CI uses, so a local pass means a CI pass
lint:
    actionlint -shellcheck= -oneline {{workflows}}/*.yml

# zizmor security audit: template injection, broad permissions, unpinned actions
audit:
    @command -v zizmor >/dev/null || { echo "zizmor missing: brew install zizmor"; exit 1; }
    zizmor {{workflows}}/

# Which reusable workflow calls which; no argument draws every entry point
graph workflow="":
    @python3 scripts/workflow-graph.py {{workflow}}

# Mermaid flowchart of templates and workflows, to paste into a PR or doc
mermaid:
    @python3 scripts/workflow-graph.py --mermaid --templates

# Jobs and needs inside one workflow, drawn by act
jobs workflow:
    @command -v act >/dev/null || { echo "act missing: brew install act"; exit 1; }
    act -W {{workflows}}/{{workflow}} -g

# Stacks and the templates each one ships
stacks:
    @python3 scripts/new-pipeline.py --list

# Install a stack's templates into a consumer repo: just new java ../my-service
new stack repo *only:
    python3 scripts/new-pipeline.py {{stack}} {{repo}} {{ if only == "" { "" } else { "--only " + only } }}

# Every script self-test CI runs; coverage-gate and react-test-verdict need PyYAML
selftest:
    #!/usr/bin/env bash
    failed=()
    for t in .github/selftest/*.test.sh; do
      echo "== $t"; "$t" || failed+=("$t")
    done
    [ ${#failed[@]} -eq 0 ] || { printf 'FAILED %s\n' "${failed[@]}"; exit 1; }

# Everything CI checks that runs offline
check: lint selftest

# Run lint (and zizmor when installed) before every commit
install-hooks:
    printf '%s\n' '#!/usr/bin/env bash' 'set -e' 'just lint' \
      'if command -v zizmor >/dev/null; then just audit; fi' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit

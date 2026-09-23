#!/usr/bin/env bash
# Fixture for the shared-validate-image-pr self-test.
#
# Stands in for a real repository gate — a pin auditor, a codegen drift check.
# It asserts the one thing a caller cannot see from outside: that gate_command
# runs on a plain checkout, from the repository root, before anything is built.
set -euo pipefail
[ -f '.github/workflows/shared-validate-image-pr.yml' ] || {
    echo "gate_command did not run from the repository root" >&2
    exit 1
}
[ -z "${IMAGE:-}" ] || {
    echo "gate_command ran with IMAGE set: it is meant to gate sources, not images" >&2
    exit 1
}
echo "Gate OK: plain checkout, repository root, no image in scope."

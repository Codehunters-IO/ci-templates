#!/usr/bin/env bash
# Asserts the shared workflow handed us the image it said it built, and that
# smoke_env reached the command.
set -euo pipefail
: "${IMAGE:?IMAGE not exported by the shared workflow}"
: "${EXPECT_MARKER:?smoke_env did not reach the smoke command}"
got=$(docker run --rm "${IMAGE}" cat /selftest)
[ "${got}" = "${EXPECT_MARKER}" ] || { echo "marker '${got}' != '${EXPECT_MARKER}'" >&2; exit 1; }
echo "Self-test OK: ${IMAGE} carries '${got}'."

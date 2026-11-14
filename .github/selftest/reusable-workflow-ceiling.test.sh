#!/usr/bin/env bash
# A workflow may call at most 20 unique reusable workflows, and crossing that
# line is not an error anyone can read.
#
# GitHub counts the whole nested tree, and counts the called workflow itself.
# Over 20, the run ends in `startup_failure` with zero jobs: no logs, no
# annotation, no check run, nothing in any API. The only visible fact is that
# the pipeline refused to start.
#
# That is what v2.9.0 did. `deploy_target: gitops` added a seventeenth leaf to
# java-main-pipeline, which already sat at exactly 20 counting itself, so the
# release took it to 21 and every java repository's trunk died at startup on
# the same commit that had been green an hour earlier. v2 had to be moved back
# to v2.8.1 by hand to restore the consumers.
#
# A tree at exactly 20 is legal and has zero headroom: the next leaf anyone
# adds repeats the outage. This warns there and fails above.
#
# The depth limit is checked for the same reason: four levels of nesting is the
# documented maximum, and the fifth fails the same mute way.
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 - <<'PY'
import pathlib
import re
import sys

import yaml

CEILING = 20
MAX_DEPTH = 4

WF = pathlib.Path(".github/workflows")
docs = {p.name: yaml.safe_load(p.read_text()) for p in sorted(WF.glob("*.yml"))}

# A remote call cannot be followed, but it occupies a slot exactly like a local
# one, so it is counted as a leaf rather than ignored.
LOCAL = re.compile(r"^\./\.github/workflows/(?P<name>[\w.-]+\.ya?ml)$")


def callees(name):
    """Workflow file names (or remote refs) this workflow calls directly."""
    doc = docs.get(name)
    if not isinstance(doc, dict):
        return []
    out = []
    for job in (doc.get("jobs") or {}).values():
        if not isinstance(job, dict):
            continue
        uses = job.get("uses")
        if not isinstance(uses, str):
            continue
        match = LOCAL.match(uses.strip())
        out.append(match.group("name") if match else uses.strip())
    return out


def tree(root):
    """Unique workflows reachable from root, including root, and the depth reached."""
    seen = {root}
    depth = 1
    frontier = [root]
    while frontier:
        nxt = []
        for current in frontier:
            for child in callees(current):
                if child not in seen:
                    seen.add(child)
                    nxt.append(child)
        if nxt:
            depth += 1
        frontier = nxt
    return seen, depth


failures = []
warnings = []
report = []

for name in docs:
    reachable, depth = tree(name)
    if len(reachable) == 1:
        continue  # calls nothing: it cannot cross either limit
    report.append((len(reachable), depth, name))
    if len(reachable) > CEILING:
        over = sorted(reachable - {name})
        failures.append(
            f"{name}: {len(reachable)} unique reusable workflows, ceiling is {CEILING}.\n"
            f"    Remove one of its {len(over)} callees, or fold two into one "
            f"workflow with a job each.\n"
            f"    Tree: {', '.join(over)}"
        )
    elif len(reachable) == CEILING:
        warnings.append(f"{name}: at {CEILING} of {CEILING}, no headroom")
    if depth > MAX_DEPTH:
        failures.append(f"{name}: nested {depth} levels deep, maximum is {MAX_DEPTH}")

for count, depth, name in sorted(report, reverse=True):
    print(f"  {count:>3} workflows  depth {depth}  {name}")

for warning in warnings:
    print(f"::warning::{warning}")

if failures:
    print()
    for failure in failures:
        print(f"::error::{failure}", file=sys.stderr)
    sys.exit(1)

print(f"\nEvery tree is within {CEILING} workflows and {MAX_DEPTH} levels.")
PY

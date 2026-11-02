#!/usr/bin/env bash
# A gate that defaults to on must stay reachable from the caller.
#
# A reusable workflow forwards nothing it has not declared. So when a leaf
# workflow declares `run_x` with `default: true` and the pipeline above it
# neither declares nor forwards that input, the default becomes the only value
# any consumer can ever get. There is no error: the input simply is not there.
#
# That is how `run_spotless` behaved until this test was written. java-build.yml
# defaulted it to true, neither java-pr-gates.yml nor the two pipelines passed it
# through, and `./gradlew spotlessCheck` therefore ran in every Java repository
# whether or not the project had the plugin. In auth-bff it did not, so Build
# failed on "Task 'spotlessCheck' not found" — and because test, qodana, owasp
# and architecture all `needs: build`, one unreachable switch cost four gates.
#
# Only `default: true` is checked. An off-by-default switch that is not forwarded
# is a feature nobody can turn on, which is visible the first time someone tries;
# an on-by-default one that is not forwarded is a gate nobody can turn off, and it
# surfaces as a failure in the consumer's repository instead.
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 - <<'PY'
import pathlib
import sys

import yaml

WF = pathlib.Path(".github/workflows")
docs = {p.name: yaml.safe_load(p.read_text()) for p in sorted(WF.glob("*.yml"))}


def workflow_call_inputs(doc):
    """`on:` parses as the boolean True under the YAML 1.1 rules PyYAML follows."""
    trigger = doc.get("on") if isinstance(doc, dict) else None
    if trigger is None and isinstance(doc, dict):
        trigger = doc.get(True)
    if not isinstance(trigger, dict):
        return None
    call = trigger.get("workflow_call")
    if call is None:
        return None
    return call.get("inputs") or {}


gaps = []
for name, doc in docs.items():
    if not isinstance(doc, dict) or workflow_call_inputs(doc) is None:
        continue
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        uses = job.get("uses", "")
        if not uses.startswith("./.github/workflows/"):
            continue
        child = docs.get(uses.rsplit("/", 1)[-1])
        if child is None:
            continue
        forwarded = set((job.get("with") or {}).keys())
        for input_name, spec in (workflow_call_inputs(child) or {}).items():
            if not input_name.startswith("run_"):
                continue
            if spec.get("default") is not True or input_name in forwarded:
                continue
            gaps.append((name, job_name, uses.rsplit("/", 1)[-1], input_name))

for gap in gaps:
    print("FAIL %s job '%s' calls %s without forwarding %s" % gap)
if not gaps:
    print("ok   every on-by-default run_* switch is reachable from the caller")
print("%d unreachable switch(es)" % len(gaps))
sys.exit(1 if gaps else 0)
PY

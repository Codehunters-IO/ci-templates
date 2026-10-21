#!/usr/bin/env python3
"""Draw which reusable workflow calls which, from the `uses:` lines alone.

`act -g` draws the jobs inside one workflow; it cannot follow a call into
another file, which is the whole shape of this repository. Stdlib only, and
line-based rather than a YAML parser, so it runs on any runner and laptop
without a pip install. That holds because every workflow here keeps jobs at
two spaces and `uses:` at four.

  workflow-graph.py                          tree of every pipeline
  workflow-graph.py java-main-pipeline.yml   tree of one workflow
  workflow-graph.py --mermaid [--templates]  Mermaid flowchart for the README
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
TEMPLATES = ROOT / "templates"
JOB = re.compile(r"^  ([A-Za-z0-9_-]+):\s*$")
LOCAL_CALL = re.compile(r"^    uses:\s*\./\.github/workflows/([\w.-]+\.ya?ml)")
REMOTE_CALL = re.compile(r"^    uses:\s*\S+/ci-templates/\.github/workflows/([\w.-]+\.ya?ml)@")


def calls(path, pattern):
    """(job id, called workflow) pairs, in file order."""
    found, job, in_jobs = [], None, False
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if not line.startswith(" "):
            in_jobs = line.startswith("jobs:")
            continue
        head = JOB.match(line) if in_jobs else None
        if head:
            job = head.group(1)
        hit = pattern.match(line) if job else None
        if hit:
            found.append((job, hit.group(1)))
    return found


def load_graph():
    return {p.name: calls(p, LOCAL_CALL) for p in sorted(WORKFLOWS.glob("*.y*ml"))}


def roots(graph):
    """Workflows no other workflow here calls: the entry points callers use."""
    called = {callee for edges in graph.values() for _, callee in edges}
    return [name for name, edges in graph.items() if edges and name not in called]


def tree(graph, name, prefix="", seen=()):
    lines = []
    edges = graph.get(name, [])
    for i, (job, callee) in enumerate(edges):
        last = i == len(edges) - 1
        cycle = "  (cycle)" if callee in seen else ""
        lines.append(f"{prefix}{'└── ' if last else '├── '}{job} → {callee}{cycle}")
        if not cycle:
            child = prefix + ("    " if last else "│   ")
            lines += tree(graph, callee, child, seen + (name,))
    return lines


def node(name):
    return re.sub(r"\W", "_", name.rsplit(".", 1)[0])


def mermaid(graph, with_templates):
    out = ["flowchart LR"]
    if with_templates:
        for tpl in sorted(TEMPLATES.glob("*.y*ml")):
            for _, callee in calls(tpl, REMOTE_CALL):
                out.append(f"  t_{node(tpl.name)}[/{tpl.name}/] --> {node(callee)}")
    for name, edges in graph.items():
        for job, callee in edges:
            out.append(f"  {node(name)}[{name}] -->|{job}| {node(callee)}[{callee}]")
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("workflow", nargs="?", help="file name under .github/workflows/")
    ap.add_argument("--mermaid", action="store_true", help="print a Mermaid flowchart")
    ap.add_argument("--templates", action="store_true", help="with --mermaid, add templates/ as callers")
    args = ap.parse_args(argv)
    graph = load_graph()
    if args.mermaid:
        print("\n".join(mermaid(graph, args.templates)))
        return 0
    if args.workflow and args.workflow not in graph:
        print(f"no workflow named {args.workflow} under .github/workflows/", file=sys.stderr)
        return 2
    for name in [args.workflow] if args.workflow else roots(graph):
        print("\n".join([name] + tree(graph, name)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

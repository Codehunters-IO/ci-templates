#!/usr/bin/env python3
"""Install one stack's templates into a consumer repository.

Does the Quick Start by hand-free: copies templates/<stack>-*.yml to the
name each template's `# Copy to:` header asks for, and replaces `<org>`.
Never overwrites a workflow the consumer already has.

  new-pipeline.py java ../my-service
  new-pipeline.py contracts ../my-contracts --only pr-full feature-build
  new-pipeline.py --list
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "templates"
COPY_TO = re.compile(r"^# Copy to:\s*(\.github/workflows/\S+\.ya?ml)", re.M)
# Installed only on request: it shares `name: PR Validation` with
# contracts-pr-develop, so both together cancel each other's runs.
OPT_IN = {"contracts-pr-full"}
DEFAULT_ORG = "Codehunters-IO"
# Spelled out rather than inferred from file names: role names have hyphens
# too (release-drafts, cleanup-packages), so a prefix guess cannot tell them apart.
STACKS = ("java", "java-library", "krakend", "react", "nginx", "contracts", "firebase", "shared")


def stack_of(name):
    """Longest stack prefix wins, so java-library-* is not java's."""
    return max((s for s in STACKS if name.startswith(s + "-")), key=len, default=None)


def catalog():
    by_stack = {}
    for f in sorted(TEMPLATES.glob("*.y*ml")):
        by_stack.setdefault(stack_of(f.stem), []).append(f)
    return {s: fs for s, fs in by_stack.items() if s}


def destination(template, stack):
    header = COPY_TO.search(template.read_text())
    if header:
        return Path(header.group(1))
    return Path(".github/workflows") / (template.name if stack == "shared" else template.name[len(stack) + 1:])


def pick(stack, files, only):
    role = lambda f: f.stem[len(stack) + 1:]
    if only:
        unknown = set(only) - {role(f) for f in files}
        if unknown:
            raise SystemExit(f"{stack} has no template(s): {', '.join(sorted(unknown))}")
        return [f for f in files if role(f) in only]
    if stack == "shared":
        # Four independent image jobs, not a set: a repo wants one or two of them.
        raise SystemExit("shared needs --only, one or more of: " + " ".join(role(f) for f in files))
    return [f for f in files if f.stem not in OPT_IN]


def install(files, stack, repo, org):
    plan = [(f, repo / destination(f, stack)) for f in files]
    taken = [str(d.relative_to(repo)) for _, d in plan if d.exists()]
    clash = {d for _, d in plan if [x for _, x in plan].count(d) > 1}
    if taken or clash:
        raise SystemExit("refusing to overwrite: " + ", ".join(taken + [str(c.relative_to(repo)) for c in clash]))
    for src, dst in plan:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(src.read_text().replace("<org>/", f"{org}/"))
        print(f"{src.name:40} → {dst.relative_to(repo)}")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("stack", nargs="?")
    ap.add_argument("repo", nargs="?", type=Path, help="consumer repository root")
    ap.add_argument("--only", nargs="+", metavar="ROLE", help="e.g. validate main-deploy")
    ap.add_argument("--org", default=DEFAULT_ORG)
    ap.add_argument("--list", action="store_true", help="show stacks and their templates")
    args = ap.parse_args(argv)
    stacks = catalog()
    if args.list or not args.stack:
        for s, fs in sorted(stacks.items()):
            print(f"{s:14} " + " ".join(f.stem[len(s) + 1:] for f in fs))
        return 0
    if args.stack not in stacks:
        raise SystemExit(f"unknown stack {args.stack}; one of: {', '.join(sorted(stacks))}")
    if not args.repo or not args.repo.is_dir():
        raise SystemExit("give the consumer repository root as the second argument")
    install(pick(args.stack, stacks[args.stack], args.only), args.stack, args.repo.resolve(), args.org)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

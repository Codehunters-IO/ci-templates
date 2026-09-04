# Rulesets

These files are definitions, not state. Writing one here changes nothing — it has to be
POSTed. As of this commit `GET /repos/Codehunters-IO/ci-templates/rulesets` returns `[]`,
so nothing in this directory is currently in force anywhere.

## What each file is for

| File | Level | Applies to |
|------|-------|-----------|
| `ruleset-develop.json` | org | `codehunters-ms-*`, `codehunters-sdk-*` — consumer repos |
| `ruleset-main.json` | org | same, `main` |
| `ruleset-krakend.json` | org | KrakenD repos, `develop` + `main` |
| `ruleset-tags.json` | org | release tags `vX.Y.Z`, immutable |
| `ruleset-ci-templates.json` | **repo** | this repository |

The four org-level files carry a `repository_name` condition. `ci-templates` matches none
of their patterns, which is why this repository ended up with no protection at all: anyone
with write access can push straight to `develop` or `main`, force-push over either, or
delete them. `main` is what every consumer's `@v1` alias resolves to.

`ruleset-ci-templates.json` has no `repository_name` condition because repo-level rulesets
do not take one.

## Applying

Repo-level (this repository):

```bash
gh api -X POST repos/Codehunters-IO/ci-templates/rulesets \
  --input .github/ruleset/ruleset-ci-templates.json
```

Org-level (the other four) needs the `admin:org` scope:

```bash
gh auth refresh -h github.com -s admin:org
gh api -X POST orgs/Codehunters-IO/rulesets --input .github/ruleset/ruleset-develop.json
```

Verify after applying — a POST that returns 201 with `"enforcement": "evaluate"` reports
violations without blocking anything:

```bash
gh api repos/Codehunters-IO/ci-templates/rulesets --jq '.[] | "\(.name) — \(.enforcement)"'
```

## Two things to know before applying the repo-level one

**Required checks must have run at least once.** The four contexts refer to jobs in
`.github/workflows/ci.yml`. Apply the ruleset before that workflow has ever run and every
PR blocks on checks GitHub has never seen.

**No `required_linear_history`.** The org files set it; this one does not, on purpose. The
release flow merges `develop` into `main` and back-merges `main` into `develop`, which
produces merge commits — `33d5104` and `d60212f` are two. Requiring linear history would
reject them.

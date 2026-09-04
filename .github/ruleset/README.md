# Rulesets

These files are definitions, not state. Writing one here changes nothing — it has to be
POSTed.

| File | Level | Applies to | In force? |
|------|-------|-----------|-----------|
| `ruleset-ci-templates.json` | **repo** | this repository, `develop` + `main` | **yes** — ruleset `22278207` |
| `ruleset-develop.json` | org | `codehunters-ms-*`, `codehunters-sdk-*`, `develop` | no |
| `ruleset-main.json` | org | same, `main` | no |
| `ruleset-krakend.json` | org | KrakenD repos, `develop` + `main` | no |
| `ruleset-tags.json` | org | release tags `vX.Y.Z`, immutable | no |

The four org-level files carry a `repository_name` condition and `ci-templates` matches
none of their patterns, which is how this repository went unprotected for so long: until
ruleset `22278207` was applied, anyone with write access could push straight to `develop`
or `main`, force-push over either, or delete them — and `main` is what every consumer's
`@v1` alias resolves to. `ruleset-ci-templates.json` has no `repository_name` condition
because repo-level rulesets do not take one.

Check what is actually in force rather than trusting this table:

```bash
gh api repos/Codehunters-IO/ci-templates/rulesets --jq '.[] | "\(.name) — \(.enforcement)"'
gh api repos/Codehunters-IO/ci-templates/rules/branches/develop --jq '.[].type'
```

The second command is the one that matters. A ruleset can exist and still not apply to the
branch you care about.

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

Editing an existing one is a `PATCH` against its id — no need to delete and recreate:

```bash
gh api -X PATCH repos/Codehunters-IO/ci-templates/rulesets/22278207 --input <file>
```

## Why the repo-level one is shaped the way it is

**Zero required approvals, no code-owner review.** Not an oversight. `CODEOWNERS` lists a
single owner, GitHub does not let anyone approve their own pull request, and
`bypass_actors` gates who can skip the rules. Requiring one approval with one owner and no
bypass would mean no pull request could ever merge. The rules that carry the weight here
are `pull_request` itself (no direct pushes), `deletion`, `non_fast_forward` and the
required checks — none of which need a second person. Raise the count to 1 or 2 the day
there is a second maintainer.

**Repository admins can bypass.** An escape hatch for the case where a required check
itself breaks. Without it a broken `ci.yml` would make the repository unmergeable with no
way back.

**No `required_linear_history`.** The org files set it; this one does not, on purpose. The
release flow merges `develop` into `main` and back-merges `main` into `develop`, which
produces merge commits — `16d4a51` and `cd6b2ac` are two recent ones. Requiring linear
history would reject them.

**Required checks must have run at least once.** The four contexts are jobs in
`.github/workflows/ci.yml`. Applying the ruleset before that workflow has ever run leaves
every pull request blocked on checks GitHub has never seen.

## One field GitHub sets on its own

The API fills in defaults this file does not declare. Most are inert, but one is not:
`require_extra_approval_for_unattributed_changes`, which the server set to `true`. With
zero approvals normally required, a pull request containing commits not attributed to a
GitHub account will still ask for one. That is usually the behaviour you want; if a pull
request is stuck asking for a reviewer for no visible reason, this is why. To turn it off,
add it to the `pull_request` parameters here and `PATCH` the ruleset.

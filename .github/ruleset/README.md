# Rulesets

These files are definitions, not state. Writing one here changes nothing — it has to be
sent to the API.

| File | Level | Applies to | In force? |
|------|-------|-----------|-----------|
| `ruleset-ci-templates-develop.json` | **repo** | this repository, `develop` | **yes** — ruleset `22278207` |
| `ruleset-ci-templates-main.json` | **repo** | this repository, `main` | **yes** — ruleset `22284847` |
| `ruleset-develop.json` | org | `codehunters-ms-*`, `codehunters-sdk-*`, `develop` | no |
| `ruleset-main.json` | org | same, `main` | no |
| `ruleset-krakend.json` | org | KrakenD repos, `develop` + `main` | no |
| `ruleset-tags.json` | org | release tags `vX.Y.Z`, immutable | no |

The four org-level files carry a `repository_name` condition and `ci-templates` matches
none of their patterns, which is how this repository went unprotected for so long: until
these two rulesets were applied, anyone with write access could push straight to `develop`
or `main`, force-push over either, or delete them — and `main` is what every consumer's
`@v1` alias resolves to. The repo-level files have no `repository_name` condition because
repo-level rulesets do not take one.

Check what is actually in force rather than trusting this table:

```bash
gh api repos/Codehunters-IO/ci-templates/rulesets --jq '.[] | "\(.name) — \(.enforcement)"'
gh api repos/Codehunters-IO/ci-templates/rules/branches/develop --jq '.[].type'
```

The second command is the one that matters. A ruleset can exist and still not apply to the
branch you care about.

## Why two rulesets and not one

`allowed_merge_methods` lives on the `pull_request` rule, and a rule applies to every ref
its ruleset includes. One ruleset covering both branches cannot ask for squash on one and
a merge commit on the other, so there is one per branch.

**`develop` is squash-only.** Feature branches land as a single commit. Nothing else is
permitted.

**`main` is merge-only.** The release pull request is `develop` → `main`, and squashing it
would give `main` a commit that shares no history with `develop`. The two branches would
diverge permanently on every release, and the back-merge would then replay changes
`develop` already has, as conflicts. This repository has been through that drift twice.
Merge-only also means nobody can squash a release by reflex — the method is not offered.

## Why the rest is shaped the way it is

**Zero required approvals, no code-owner review.** Not an oversight. `CODEOWNERS` lists a
single owner, GitHub does not let anyone approve their own pull request, and
`bypass_actors` gates who can skip the rules. Requiring one approval with one owner and no
bypass would mean no pull request could ever merge. The rules that carry the weight are
`pull_request` itself (no direct pushes), `deletion`, `non_fast_forward` and the required
checks — none of which need a second person. Raise the count to 1 or 2 the day there is a
second maintainer.

**Repository admins can bypass.** An escape hatch for the case where a required check
itself breaks. Without it a broken `ci.yml` would make the repository unmergeable with no
way back.

**No `required_linear_history`.** The org files set it; these do not, on purpose. It is
incompatible with the merge commits the release flow produces on `main` — `16d4a51` and
`cd6b2ac` are two.

**Required checks must have run at least once.** The four contexts are jobs in
`.github/workflows/ci.yml`. Applying a ruleset before that workflow has ever run leaves
every pull request blocked on checks GitHub has never seen.

## Applying

Creating one is a `POST`; **updating an existing one is a `PUT` against its id, not a
`PATCH`** — `PATCH` answers `404` here even though `GET` on the same id works, which reads
like a permissions problem and is not.

```bash
# create
gh api -X POST repos/Codehunters-IO/ci-templates/rulesets \
  --input .github/ruleset/ruleset-ci-templates-develop.json

# update in place
gh api -X PUT repos/Codehunters-IO/ci-templates/rulesets/22278207 \
  --input .github/ruleset/ruleset-ci-templates-develop.json
```

Org-level (the other four) needs the `admin:org` scope:

```bash
gh auth refresh -h github.com -s admin:org
gh api -X POST orgs/Codehunters-IO/rulesets --input .github/ruleset/ruleset-develop.json
```

## One field GitHub sets on its own

The API fills in defaults these files do not declare. Most are inert, but one is not:
`require_extra_approval_for_unattributed_changes`, which the server sets to `true`. With
zero approvals normally required, a pull request containing commits not attributed to a
GitHub account will still ask for one. That is usually the behaviour you want; if a pull
request is stuck asking for a reviewer for no visible reason, this is why. To turn it off,
add it to the `pull_request` parameters here and `PUT` the ruleset.

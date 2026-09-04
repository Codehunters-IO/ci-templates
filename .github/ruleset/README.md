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
breaks the release itself, not just the history. `shared-tag-release` derives the version
from `git log "${LAST_TAG}..HEAD"`. A squashed release gives `main` a single commit whose
subject is the pull request title — so a release carrying a `feat` computes as a patch.
Measured on the v1.3.0 release: merged, it produced `v1.3.0`; squashed, the same content
would have produced `v1.2.1`, and `v1` would have moved to a version that understates what
changed. Merge-only also means nobody can squash a release by reflex — the method is not
offered.

## Why there is no back-merge

Classic GitFlow back-merges `main` into `develop` after a release, because `main` receives
hotfixes of its own. Here it does not: nothing is ever committed to `main` except the
release merge, and the release merge is `develop`'s own content. `main` therefore never
holds a change `develop` lacks.

The branches still read as diverged, because the merge commits themselves live only on
`main`. That is topology, not content. After the v1.3.1 release:

```console
$ gh api repos/Codehunters-IO/ci-templates/compare/develop...main \
    --jq '"\(.status) ahead_by=\(.ahead_by) files=\(.files|length)"'
diverged ahead_by=2 files=0
```

Two commits, zero files. Both are merge commits touching nothing.

A back-merge pull request would therefore carry an empty diff, and `develop` is squash-only
— squashing nothing produces nothing, and `main`'s merge commits would still not be
ancestors of `develop`. The divergence would survive the ceremony intended to end it. So
there is no back-merge step, and the `develop`-only count growing by one per release is
expected.

This holds only while `main` receives nothing but release merges. The day something lands
on `main` directly — a hotfix that cannot wait for `develop` — `develop` needs that change
back, and squash-only leaves cherry-pick as the path. Add `merge` to `develop`'s
`allowed_merge_methods` at that point rather than in advance.

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

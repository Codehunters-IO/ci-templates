# Rulesets

These files are definitions, not state. Writing one here changes nothing — it has to be
sent to the API.

| File | Level | Applies to | In force? |
|------|-------|-----------|-----------|
| `ruleset-ci-templates-develop.json` | **repo** | this repository, `develop` | **yes** — ruleset `22278207` |
| `ruleset-ci-templates-main.json` | **repo** | this repository, `main` | **yes** — ruleset `22284847` |
| `ruleset-ci-templates-hardening.json` | **repo** | this repository, `develop` + `main` | **yes** — ruleset `23976465` |
| `ruleset-ci-templates-tags.json` | **repo** | this repository, `vX.Y.Z` tags | **yes** — ruleset `23957169` |
| `ruleset-ci-templates-tag-alias.json` | **repo** | this repository, the `vX` alias | **yes** — ruleset `23957170` |
| `ruleset-develop.json` | org | `codehunters-ms-*`, `codehunters-sdk-*`, `develop` | no |
| `ruleset-main.json` | org | same, `main` | no |
| `ruleset-krakend.json` | org | KrakenD repos, `develop` + `main` | no |
| `ruleset-tags.json` | org | release tags `vX.Y.Z`, immutable | no |

The four org-level files carry a `repository_name` condition and `ci-templates` matches
none of their patterns, which is how this repository went unprotected for so long: until
the repo-level rulesets were applied, anyone with write access could push straight to
`develop` or `main`, force-push over either, or delete them — and `main` is what every
consumer's `@v1` alias resolves to. The repo-level files have no `repository_name`
condition because repo-level rulesets do not take one.

**The org-level files cannot be applied at all on the current plan.** It is not a question
of scope: `gh api orgs/Codehunters-IO/rulesets` answers `403 Upgrade to GitHub Team`
whatever the token. They are kept as the definitions to apply the day the organisation is
on Team or above; until then every protection this repository has must be repo-level.

Check what is actually in force rather than trusting this table:

```bash
gh api repos/Codehunters-IO/ci-templates/rulesets --jq '.[] | "\(.name) — \(.enforcement)"'
gh api repos/Codehunters-IO/ci-templates/rules/branches/develop --jq '.[].type'
```

The second command is the one that matters. A ruleset can exist and still not apply to the
branch you care about.

## Why the branches need three rulesets

GitHub evaluates every ruleset that matches a ref and applies the union, so a branch's
protection is the sum of the rulesets covering it, not whichever one you happen to open.
The split is by *what varies*, so no policy is written down twice:

| Ruleset | Holds | Because |
|---|---|---|
| `…-develop` / `…-main` | `deletion`, `non_fast_forward`, `pull_request` | `allowed_merge_methods` differs per branch |
| `…-hardening` | `required_signatures`, `required_status_checks` | identical for both branches |

`allowed_merge_methods` lives on the `pull_request` rule, and a rule applies to every ref
its ruleset includes. One ruleset covering both branches cannot ask for squash on one and
a merge commit on the other, so that rule has to be stated once per branch. Everything
that is the same for both is stated once, in the hardening ruleset — keeping the required
checks in two files meant two lists to forget to update, and two `strict` flags that could
disagree with no obvious winner.

Check the union rather than any single file:

```bash
gh api repos/Codehunters-IO/ci-templates/rules/branches/develop --jq '[.[].type]|unique'
```

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

## Why the tags need two rulesets

`v1` is what every consumer resolves. Until these were applied nothing protected it:
`gh api repos/Codehunters-IO/ci-templates/rules/branches/refs%2Ftags%2Fv1` returned zero
rules, so anyone with write access could delete the alias or repoint it at an arbitrary
commit, and the next pipeline in every consuming repository would run whatever they chose.
No pull request, no check, no record.

The two tag rulesets exist because the release flow treats the two kinds of tag in
opposite ways. `shared-tag-release` **creates** `vX.Y.Z` once and never touches it again;
`release.yml` then **force-moves** the `vX` alias on every single release:

```bash
git tag -f -a "$MAJOR" -m "Floating alias for ${VERSION_TAG}"
git push origin "refs/tags/${MAJOR}" --force
```

So `vX.Y.Z` can be sealed against `update`, `deletion` and `non_fast_forward`, while the
alias can only be protected against `deletion` — blocking its update would break the
release at the "Move floating major tag" step. Hence one ruleset per pattern, with the
alias ruleset excluding `refs/tags/v[0-9]*.[0-9]*.[0-9]*` so the two never overlap.

**Neither blocks `creation`,** and that is forced, not chosen. `release.yml` pushes tags as
`github-actions[bot]` with `GITHUB_TOKEN`, which holds write, not admin, so it does not
inherit the `bypass_actors` escape hatch. Granting the GitHub Actions app an explicit
bypass is not available here either — a repo-level ruleset answers
`422 Actor GitHub Actions integration must be part of the ruleset source or owner
organization`. Blocking creation would therefore block the release itself. The residual
risk is that someone can still hand-cut a tag, and `shared-tag-release` derives the next
version from `git tag -l --sort=-v:refname | head -n1`, so a bogus `v9.9.9` would poison
the following release. Nothing here prevents that; it is the price of keeping the release
able to tag at all.

Verified by probe rather than by reading the JSON, with `bypass_actors` temporarily
emptied so the admin escape hatch could not mask the result:

| Operation | Expected | Result |
|-----------|----------|--------|
| create `v0.0.999` | allowed | allowed |
| force-move `v0.0.999` | rejected | rejected |
| delete `v0.0.999` | rejected | rejected |
| create `v0` | allowed | allowed |
| force-move `v0` | allowed | allowed |
| delete `v0` | rejected | rejected |

The two probe tags were deleted afterwards and the bypass restored.

## Why the rest is shaped the way it is

**Zero required approvals, no code-owner review.** Not an oversight. `CODEOWNERS` lists a
single owner, GitHub does not let anyone approve their own pull request, and
`bypass_actors` gates who can skip the rules. Requiring one approval with one owner and no
bypass would mean no pull request could ever merge. The rules that carry the weight are
`pull_request` itself (no direct pushes), `deletion`, `non_fast_forward` and the required
checks — none of which need a second person. Raise the count to 1 or 2 the day there is a
second maintainer.

**Repository admins can bypass, but only through a pull request.** `bypass_mode` is
`pull_request`, not `always`. The escape hatch is still there for the case that justifies
it — a broken `ci.yml` would otherwise make the repository unmergeable with no way back,
and an admin can still merge a pull request over a failing required check. What it no
longer allows is a direct push to `develop` or `main` that skips the pull request
entirely. The tag rulesets stay on `always`: a tag has no pull request to bypass through,
so `pull_request` there would mean a bad tag could never be removed by anyone.

**`required_signatures`.** Every commit landing on `develop` or `main` must carry a valid
signature. In practice nothing has to change in anyone's workflow: commits reach these
branches only as the squash or merge commit GitHub itself creates, and GitHub signs those
with its own key. Two commits already in history predate the rule and are unsigned
(`d4bab10`, `656c896`, June–July 2026); the rule is evaluated on push, so they are not
affected and do not need rewriting.

**`strict_required_status_checks_policy`.** A pull request must be up to date with its
base before it can merge. Without it, checks that went green against an older `develop`
still count, so two pull requests that pass independently can merge into a state neither
was tested against. The cost is real — a merge now invalidates every other open pull
request until it is updated — and is worth paying in a repository whose output is other
repositories' CI.

**Branch deletion on merge is a repository setting, not a rule.** `delete_branch_on_merge`
is on, set with
`gh api -X PATCH repos/Codehunters-IO/ci-templates -f delete_branch_on_merge=true`. No
ruleset can express it, which is why it is recorded here rather than in one of these
files.

**No `required_linear_history`.** The org files set it; these do not, on purpose. It is
incompatible with the merge commits the release flow produces on `main` — `16d4a51` and
`cd6b2ac` are two.

**Required checks must have run at least once.** The six contexts are jobs in
`.github/workflows/ci.yml`, and they live in the hardening ruleset. Applying a ruleset
before that workflow has ever run leaves every pull request blocked on checks GitHub has
never seen.

**The self-test jobs are deliberately not required.** `selftest-build-publish-image` and
`selftest-validate-image-pr` are filtered by `paths`, so they do not start on a pull
request that touches nothing under `.github/selftest/**` or the two workflows they
exercise. A required check that never starts is a pull request that never merges, so
requiring them would deadlock every unrelated change. They still run, and still have to be
green, on the pull requests that do touch those files.

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

Org-level (the other four) needs the `admin:org` scope **and an organisation on GitHub
Team or above**. On the current plan the second command answers `403 Upgrade to GitHub
Team` and there is nothing a token can do about it:

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

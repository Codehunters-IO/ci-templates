# CI Templates

Reusable GitHub Actions workflows for Java, Krakend, React and Solidity/Hardhat projects following a GitFlow branching strategy.

## Stacks

| Stack | Pipelines | Templates |
|-------|-----------|-----------|
| Java (Spring Boot) | `java-main-pipeline.yml` · `java-pr-pipeline.yml` | `templates/java-*.yml` |
| Krakend | `krakend-main-pipeline.yml` | `templates/krakend-*.yml` |
| NGINX (ingress) | `nginx-main-pipeline.yml` | `templates/nginx-*.yml` |
| React | `react-main-pipeline.yml` | `templates/react-*.yml` |
| Contracts (Hardhat/Solidity) | `contracts-main-pipeline.yml` | `templates/contracts-*.yml` |

## GitFlow

The diagram below is the **Java and KrakenD** flow, where `main` reaches `cert` and
production is a separate approval-gated step. React, NGINX and Contracts differ: their
`release/*` branches deploy to `staging` and `main` goes straight to `production`. See
[Templates by stack](#templates-by-stack) and [Environments](#environments).

```
feature/* ──► build
     │
     ▼ (PR to develop)      build → test → coverage → owasp → architecture
     │                       └── uses java-pr-pipeline.yml (quality gates only)
     │
     ▼ (merge to develop)   build → test → coverage → owasp
     │                              → artifact (ECR) → deploy (DEVELOP)
     │                              → delete merged feature branch
     │                              → auto-create branch release/vX.Y.Z (semver)   ← no deploy
     │                              → auto-open PR release/vX.Y.Z -> main, changelog in body
     │                       └── uses java-main-pipeline.yml
     │
     ▼ (release/vX.Y.Z)     PR is already open — review & merge when ready (stabilization branch — no deploy)
     │
     ▼ (merge to main)      build → artifact (ECR) → deploy (CERT)
     │                              → delete merged release branch
     │
     ▼ ("Release to Production"  │  workflow_dispatch from main, input: version vX.Y.Z)
            validate (from main, vX.Y.Z, unused) → deploy (PROD, Environment approval)
                                                  → create tag vX.Y.Z + GitHub Release
```

> **Environments map to branches/tags.** `develop` → `develop`, `main` → `cert`, prod release → `prod`.
>
> **Release branch:** every merge to `develop` auto-creates a `release/vX.Y.Z` branch (semver from
> commit messages) and **opens a PR** `release/vX.Y.Z -> main` with the changelog (commit subjects
> since `main`) in the PR body, so whoever approves it sees what's shipping. It does **not** deploy.
> If a PR for that branch is already open, it's reused (not duplicated) on subsequent pushes to
> `develop`. Merging it to `main` deploys to `cert`.
>
> **Production:** promoted via the manual **`Release to Production`** workflow (`workflow_dispatch`,
> run **only from `main`** with a `version` input). It deploys to `prod` behind the `prod` Environment's
> *required reviewers*, then creates the git tag `vX.Y.Z` + GitHub Release **only after** a successful
> approved deploy (no orphan tags, no hand-pushed tags).
>
> **Branch cleanup** runs on every merge (develop/main): the merged `feature/*` or `release/vX.Y.Z`
> branch is deleted — but only after verifying its PR was actually merged. `develop`/`main` are never
> deleted. Cleanup never fails the pipeline.

## Quick Start

1. Copy the templates for your stack from `templates/` into your repo's `.github/workflows/`.
   Each template's header carries the filename it expects once copied — the stack prefix
   exists to keep `templates/` browsable and is dropped on the way in:

   ```bash
   cp templates/java-validate.yml        .github/workflows/validate.yml        # feature/* push + PR → develop
   cp templates/java-develop-deploy.yml  .github/workflows/develop-deploy.yml  # develop → develop env (+ auto release branch)
   cp templates/java-main-deploy.yml     .github/workflows/main-deploy.yml     # main → cert
   cp templates/java-tag-deploy.yml      .github/workflows/tag-deploy.yml      # prod (workflow_dispatch from main)
   ```

   The `validate.yml` name is not cosmetic: its job id `validate` is what produces the
   required status check context `validate / PR Quality Gates` that the org ruleset on
   `develop` expects. Rename the job and the branch protection stops matching.

2. Replace `<org>` with your GitHub organization in each template:
   ```yaml
   uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
   ```

3. Configure the required secrets (see below) and declare the GitHub Environments your
   stack's templates reference — they differ per stack, see [Environments](#environments).

## Templates by stack

Not every stack ships the same set, and the gaps are real rather than oversights waiting
to be filled. A dash means no template exists for that step.

| Stack | `feature/*` push | PR → `develop` | `develop` | `release/*` | `main` | Production |
|---|---|---|---|---|---|---|
| Java | `java-validate` | `java-validate` | `java-develop-deploy` | — | `java-main-deploy` | `java-tag-deploy` |
| KrakenD | `krakend-feature-build` | `krakend-pr-develop` | `krakend-develop-deploy` | — | `krakend-main-deploy` | `krakend-tag-deploy` |
| React | `react-feature-build` | `react-pr-develop` | `react-develop-deploy` | `react-release-deploy` | `react-main-deploy` | — |
| NGINX | `nginx-feature-build` | `nginx-pr-develop` | `nginx-develop-deploy` | `nginx-release-deploy` | `nginx-main-deploy` | — |
| Contracts | `contracts-feature-build` | `contracts-pr-develop` · `contracts-pr-full` | `contracts-develop-build` | `contracts-release-publish` | `contracts-main-deploy` | — |

Three things that table is saying out loud:

- **Java covers feature pushes and PRs with one file.** `java-validate.yml` triggers on
  both, which is why there is no `java-feature-build.yml` or `java-pr-develop.yml` to copy.
- **`release/*` deploys on three stacks and not on Java.** React, NGINX and Contracts push
  `release/**` to a `staging` environment. Java's release branch carries the PR to `main`
  and deploys nothing.
- **Only Java and KrakenD have a production template.** React, NGINX and Contracts treat
  `main` as production directly (see the environment table below); there is no
  approval-gated `workflow_dispatch` promotion for them.

Four stack-agnostic templates sit alongside these, covering the whole life of a
container image: `shared-validate-image-pr.yml` before the merge,
`shared-build-publish-image.yml` at the merge, `shared-scan-published-images.yml`
weekly afterwards, and `shared-cleanup-packages.yml` for what the registry
accumulates. Each is covered in its own section.

## Usage examples

Every example assumes `<org>` replaced and `secrets: inherit` on the job — the reusable
workflows read secrets from the caller, and omitting it produces a deploy that fails at the
first AWS step with nothing obviously wrong in the log.

### Smallest useful consumer

Build and test on every PR to `develop`, nothing else:

```yaml
name: Validation

on:
  pull_request:
    branches: [develop]

jobs:
  validate:
    uses: <org>/ci-templates/.github/workflows/java-pr-pipeline.yml@v1
    with:
      run_test: true
    secrets: inherit
```

### Java — deploy to develop on merge

```yaml
name: Deploy to Develop

on:
  push:
    branches: [develop]

permissions:
  contents: write        # the release job creates release/vX.Y.Z and opens its PR
  id-token: write        # OIDC; drop only if you are on static AWS keys
  checks: write
  pull-requests: write

jobs:
  pipeline:
    if: ${{ !contains(github.event.head_commit.message, '[skip ci]') }}
    uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
    with:
      run_build: true
      run_test: false            # already gated on the PR — see the note below
      run_artifact: true
      artifact_registry: 'ecr'
      run_deploy: true
      deploy_target: 'ec2-vpn'
      environment: 'develop'
      run_cleanup: true
      run_release: true
      release_target_branch: 'main'
    secrets: inherit
```

`run_test: false` on `develop` is deliberate in the shipped template: the same commit
already passed the PR gate, and re-running the suite on the merge result delays the deploy
without testing anything new. Turn it back on if your `develop` receives direct pushes.

### React — the full branch set

React needs five files because its `release/**` branch deploys where Java's does not:

```bash
cp templates/react-feature-build.yml   .github/workflows/feature-build.yml
cp templates/react-pr-develop.yml      .github/workflows/pr-develop.yml
cp templates/react-develop-deploy.yml  .github/workflows/develop-deploy.yml
cp templates/react-release-deploy.yml  .github/workflows/release-deploy.yml   # → staging
cp templates/react-main-deploy.yml     .github/workflows/main-deploy.yml      # → production
```

### Deploying through a VPN

`ec2-vpn` is for an EC2 whose private IP is only reachable over WireGuard. The runner
raises `wg0`, deploys, and tears it down:

```yaml
with:
  run_deploy: true
  deploy_target: 'ec2-vpn'
  environment: 'develop'
secrets: inherit          # WG_* secrets travel through inherit
```

The six `WG_*` secrets belong to the **environment**, not the repository, because the
tunnel differs per environment. Setting them at repository level makes `develop` and `cert`
deploy through the same tunnel and one of them reaches the wrong host.

### OIDC instead of static AWS keys

```yaml
jobs:
  pipeline:
    uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
    permissions:
      contents: write
      packages: write
      issues: write
      id-token: write     # required, and the caller has to grant it
    with:
      aws_role_to_assume: 'arn:aws:iam::123456789012:role/github-actions-deploy'
    secrets: inherit
```

Setting `aws_role_to_assume` is enough — the static keys are read only when it is empty.
The trust policy the role needs is in [AWS authentication](#aws-authentication).

### Running the JVM jobs inside a prebuilt image

```yaml
with:
  container_image: 'ghcr.io/codehunters-io/ci-base-images:1.0.0'
```

Skips `actions/setup-java` in `java-build`, `java-test`, `java-owasp`, `java-architecture`
and `java-artifact-dependency-github`. Use the `-graalvm` tag where `./gradlew nativeCompile`
runs. The Docker artifact and deploy jobs stay on the runner in every stack.

### Contracts — gating on your own coverage rule

```yaml
with:
  run_coverage: true
  coverage_command: './scripts/check-coverage.sh'   # its exit code fails the job
```

Prefer this over `coverage_threshold` whenever the real rule is anything other than a
global line percentage — see [Two coverage gates](#two-coverage-gates-and-which-one-to-use).

### Publishing container images

```yaml
jobs:
  images:
    uses: <org>/ci-templates/.github/workflows/shared-build-publish-image.yml@v1
    permissions:
      packages: write
      security-events: write     # omitting this silently loses the scan upload
    with:
      images: |
        [
          {"name": "api", "dockerfile": "Dockerfile", "scan_severity": "HIGH,CRITICAL"},
          {"name": "ci",  "dockerfile": "docker/ci.Dockerfile", "scan_severity": "CRITICAL"}
        ]
      smoke_command: 'docker run --rm "$IMAGE" --version'
    secrets: inherit
```

### Pinning a version that will not move

```yaml
uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1.4.1
```

Use this when a pipeline must not pick up anything, including fixes. `@v1` is the normal
choice; `@main` only to test an unreleased change on purpose.

## Versioning

Templates pin a release, not a branch:

```yaml
uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
```

`v1` is a floating alias that moves to the newest `v1.x.y`. Pinning it means a
consumer picks up fixes and backward-compatible additions without editing its
workflows, and never picks up a breaking change unannounced. Pin an exact
release such as `@v1.4.1` when a pipeline must not move at all, and `@main`
only to test an unreleased change on purpose.

Releases are cut automatically: every push to `main` runs `release.yml`, which
derives the version from the commits since the last tag, creates `vX.Y.Z` plus a
GitHub Release, and re-points `v1`.

| Commit contains | Bump |
|---|---|
| `MAJOR` or `BREAKING CHANGE` | major — `v2.0.0`, and `v1` stops moving |
| `feat` | minor |
| anything else | patch |

A major bump leaves `v1` frozen at the last 1.x release, so consumers pinned to
`@v1` keep working until they choose to move to `@v2`.

## Deprecations

Eleven per-language workflows exist only so that existing callers keep working.
They carry `[DEPRECATED]` in their name, emit a warning when called, and are
**scheduled for removal in v2**. Pinning `@v1` keeps them working until you
migrate.

Ten of them forward to a `shared-*` equivalent with identical inputs, so
migrating is a one-line change to the path:

| Deprecated | Call instead |
|---|---|
| `java-commit-lint.yml`, `krakend-commit-lint.yml`, `react-commit-lint.yml` | `shared-commit-lint.yml` |
| `java-delete-branch.yml`, `krakend-delete-branch.yml`, `react-delete-branch.yml` | `shared-delete-branch.yml` |
| `java-artifact-docker-ecr.yml`, `krakend-artifact-docker-ecr.yml` | `shared-artifact-docker-ecr.yml` |
| `krakend-deploy-ec2.yml` | `shared-deploy-ec2.yml` |
| `java-semver.yml` | `shared-semver.yml` |

`java-deploy-ec2.yml` is the exception. It also forwards to
`shared-deploy-ec2.yml`, but it is not a drop-in: it accepts `spring_profiles`,
which the shared workflow does not, and folds it into `container_env_vars`
along with the Spring context path. Migrating means doing that mapping at the
call site:

```yaml
container_env_vars: |
  SPRING_PROFILES_ACTIVE=<profiles>,<environment>
  SERVER_CONTEXT_PATH=/<repository-name>
```

The `*-main-pipeline.yml` entrypoints already call the `shared-*` workflows
directly — verified, none of the five references a deprecated workflow — so a
repository consuming a pipeline rather than an individual workflow is
unaffected by all of this.

## Deploy Targets

The main pipelines accept a `deploy_target` input:

| Value | Description | Shared workflow |
|-------|-------------|-----------------|
| `ec2` | SSH deploy to an EC2 with public/private IP reachable from the runner | `shared-deploy-ec2.yml` |
| `ec2-vpn` | SSH deploy to an EC2 with private IP reachable **only via WireGuard VPN**. The runner brings up a `wg0` tunnel, deploys, and tears it down. | `shared-deploy-ec2-vpn.yml` |
| `eks` | Deploy to an EKS cluster (plain manifests or Helm) | `shared-deploy-eks.yml` |

Example:

```yaml
jobs:
  pipeline:
    uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
    with:
      run_build: true
      run_test: true
      run_artifact: true
      run_deploy: true
      deploy_target: 'ec2-vpn'   # ec2 | ec2-vpn | eks
      environment: 'develop'
    secrets: inherit
```

## Shared workflows with no template yet

Two reusable workflows are complete and callable but ship no template, so nothing in this
repository references them and they are easy to mistake for dead code. They are not — they
cover cases the templated path does not.

### `shared-deploy-ec2-vpn-compose.yml`

Deploys a **multi-service `docker compose` stack** to an EC2 host over WireGuard. The
templated `ec2-vpn` target deploys one image pulled from ECR; this one syncs the repository
itself — compose file plus config directories — and runs `docker compose up -d`, letting
compose pull upstream images. It is the shape an observability stack needs, where there is
nothing of yours to build.

| Input | Default | |
|---|---|---|
| `compose_file` | `docker-compose.yml` | Compose file at the repository root |
| `external_networks` | `codehunters_net` | Networks to create if missing (space-separated) |
| `external_volumes` | `shared_logs` | Volumes to create if missing (space-separated) |
| `verify_vpn_connectivity` | `false` | Ping the host before deploying |
| `environment` | `develop` | GitHub Environment to bind |

Takes the same six `WG_*` secrets as `shared-deploy-ec2-vpn.yml`, plus `STACK_ENV_FILE` for
the stack's own `.env`.

### `shared-validate-source-branch.yml`

Fails a pull request whose source branch does not match an allowed prefix. Useful where the
branching model is a convention nobody enforces and `release/` branches start appearing as
`releases/`.

| Input | Required | |
|---|---|---|
| `target_branch` | yes | Branch being merged into (`develop` or `main`) |
| `allowed_prefixes` | no | Comma-separated, e.g. `feature/,fix/,chore/` |

Call either directly until a template exists:

```yaml
jobs:
  branch-name:
    uses: <org>/ci-templates/.github/workflows/shared-validate-source-branch.yml@v1
    with:
      target_branch: develop
      allowed_prefixes: 'feature/,bugfix/,hotfix/'
```

## Token permissions

Every workflow declares the `GITHUB_TOKEN` permissions it needs. Before this,
none of them did, which means each job ran with whatever the calling
repository's default happened to be — on repositories created before GitHub
changed the default, that is write-all: a linting job could push to `main`.

The declarations are derived from what each workflow actually does, not from a
template:

| Workflows | Permissions | Why |
|-----------|-------------|-----|
| Most build, test and deploy jobs | `contents: read` | They read the repository and nothing else |
| `*-build`, `*-test`, `*-owasp`, `java-architecture`, `contracts-*` | `+ packages: read` | They run inside a container pulled from GHCR |
| `java-artifact-docker-github`, `java-artifact-dependency-github` | `+ packages: write` | They publish to GitHub Packages |
| `shared-release`, `shared-semver`, `shared-tag-release`, `*-delete-branch` | `contents: write` | They push a branch, a tag, or delete a ref |
| `shared-create-issue-on-failure` | `+ issues: write` | It opens an issue |
| `*-main-pipeline`, `java-pr-pipeline` | union of the above | A caller's grant is the ceiling for everything beneath it |

That last row is the one to understand. A reusable workflow can only *narrow*
what its caller granted, never widen it. An orchestrator that calls
`shared-tag-release` therefore has to hold `contents: write` itself, even
though it pushes nothing directly — and the narrow declarations on the leaves
are what keep that grant from reaching the jobs that have no business with it.

## AWS authentication

Two paths. The default is unchanged, so nothing needs to move today.

**Static keys** — `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` repository
secrets. This is what every AWS workflow used, and it is a credential nobody
rotates, that does not expire, and that anyone with write access to the
repository can exfiltrate through a workflow change.

**OIDC** — set `aws_role_to_assume` to an IAM role ARN and no static key is
sent at all. GitHub mints a token scoped to this repository that expires with
the job:

```yaml
jobs:
  pipeline:
    uses: Codehunters-IO/ci-templates/.github/workflows/java-main-pipeline.yml@v1
    permissions:
      contents: write
      packages: write
      issues: write
      id-token: write     # required, and the caller has to grant it
    with:
      aws_role_to_assume: 'arn:aws:iam::123456789012:role/github-actions-deploy'
```

The role needs a trust policy naming GitHub's OIDC provider and restricting
`token.actions.githubusercontent.com:sub` to this repository — without that
`sub` condition any repository on GitHub can assume it.

Both keys are only read when `aws_role_to_assume` is empty; passing both would
make the action assume the role *with* the static key, leaving it in play.

## Required Secrets

Configure in **Settings → Secrets and variables → Actions**.

### AWS / ECR (for build & push)

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key for ECR push and runtime (injected into the container) |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `AWS_ECR_URL` | ECR registry URL (e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com`). **Must be the SAME AWS account as the access key** — the artifact job pushes to the creds' account registry and deploy pulls from this URL; a mismatch causes a cross-account `pull access denied`. |

### EC2 (`deploy_target: ec2` or `ec2-vpn`)

| Secret | Description |
|--------|-------------|
| `AWS_EC2_HOST` | EC2 IP or hostname (private IP when using `ec2-vpn`) |
| `AWS_EC2_USER` | SSH username (`ubuntu`, `ec2-user`, …) |
| `AWS_EC2_SSH_KEY` | SSH private key (PEM) |
| `AWS_APP_PORT` | External port exposed by the container |

### How EC2 deploys handle secrets

Two places these used to sit in the clear on the host.

**The remote command line.** The deploy environment was interpolated into the
`ssh` command, making it the remote process's argv — readable by `ps` for any
user on the box while the deploy ran. It now travels over stdin into a
mode-600 file, sourced and removed on the far side.

**`docker-compose.yml`.** `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` were
written into it in clear text, and that file persists in the deploy directory
with default permissions long after the deploy finishes. They now go to
`.aws.env`, created under `umask 077` and pulled in through compose's
`env_file`.

Two things this does **not** fix, both worth knowing:

- The values still become container environment, so `docker inspect` shows
  them. Only not sending them removes that.
- `container_env_vars` is still written inline into `docker-compose.yml`. If a
  consumer puts a database password there, it is in that file. Moving it would
  change substitution semantics for every consumer at once, so it is a separate
  decision rather than a side effect of this one.

The real fix for the credentials is to stop shipping them:

```yaml
with:
  inject_aws_credentials: false
```

Give the instance an IAM role and the application reads short-lived credentials
from the instance metadata service, with no long-lived key on the box at all.
The input defaults to `true` and warns at run time; it is going away in v2.

### WireGuard VPN (`deploy_target: ec2-vpn` only)

| Secret | Required | Description |
|--------|----------|-------------|
| `WG_PRIVATE_KEY` | Yes | WireGuard client private key |
| `WG_ADDRESS` | Yes | Client tunnel address (e.g., `10.0.0.3/24`) |
| `WG_DNS` | No | DNS server for the tunnel (e.g., `1.1.1.1`) |
| `WG_PEER_PUBLIC_KEY` | Yes | WireGuard server public key |
| `WG_PEER_ALLOWED_IPS` | Yes | Allowed IPs routed through the tunnel (e.g., `10.0.0.0/16`) |
| `WG_PEER_ENDPOINT` | Yes | Server endpoint `host:port` (e.g., `44.209.64.95:51820`) |

### SonarQube (`code_analysis: 'sonar'`)

| Secret | Description |
|--------|-------------|
| `SONAR_HOST_URL` | SonarQube server URL |
| `SONAR_TOKEN` | SonarQube authentication token |

### Notifications (Slack)

Notifications are **built into the pipelines** — consumer repos add nothing. Each
`*-main-pipeline` ends with a `notify` job (`if: always()`) that calls the reusable
`shared-notifications.yml` with the aggregate `status`; everything else (kind, branch,
actor, PR title/author/reviewers, commit description, failed stage on failure,
environment) is auto-derived from context. PR runs flow through `*-main-pipeline` too,
so the same job covers deploys and PRs.

Delivery uses a **Slack bot token** via `chat.postMessage`, with the channel chosen by
run kind:

| What | Where | Value |
|------|-------|-------|
| `SLACK_BOT_TOKEN` | org **secret** | Bot User OAuth token `xoxb-…`, scope `chat:write` (+ `chat:write.public`) |
| `SLACK_CHANNEL_PR` | org **variable** | channel for PR runs (e.g. `pipeline-prs`) |
| `SLACK_CHANNEL_DEPLOY` | org **variable** | channel for deploy runs (e.g. `deployments`) |
| `SLACK_CHANNEL` | org **variable** | fallback channel |

The token propagates into the reusable via `secrets: inherit` (already set on every
pipeline job). If the token or the matching channel is unset, the notifier warns and skips.

### Issue Tracking

Automatically creates a GitHub issue when the pipeline fails, assigned to the commit actor. Uses the built-in `GITHUB_TOKEN` — no additional secrets required.

| Input | Description | Default |
|-------|-------------|---------|
| `run_create_issue_on_failure` | Create GitHub issue on failure | `false` |
| `issue_labels` | Labels for the issue (comma-separated) | `bug,pipeline-failure` |

Example:
```yaml
with:
  run_create_issue_on_failure: true
  issue_labels: 'bug,pipeline-failure,urgent'
```

> **Tip:** Set notification secrets as organization-level secrets so all repos inherit them.

### Optional

| Secret | Used by |
|--------|---------|
| `NVD_API_KEY` | OWASP Dependency Check (`run_owasp: true`) |
| `QODANA_TOKEN` | Qodana (`code_analysis: 'qodana'`) |

> The release flow **creates the `release/vX.Y.Z` branch and opens its PR to `main`** via
> `GITHUB_TOKEN` — no PAT is needed. The prod release tag is created by GitHub Actions, which
> bypasses the tag ruleset (see Rulesets below).

## Directory Structure

```
ci-templates/
├── .github/workflows/            # Reusable workflows
│   ├── java-main-pipeline.yml
│   ├── java-pr-pipeline.yml
│   ├── contracts-main-pipeline.yml
│   ├── contracts-sdk-test.yml
│   ├── contracts-e2e.yml
│   ├── contracts-analysis.yml
│   ├── krakend-main-pipeline.yml
│   ├── react-main-pipeline.yml
│   ├── shared-deploy-ec2.yml
│   ├── shared-deploy-ec2-vpn.yml
│   ├── shared-deploy-eks.yml
│   ├── shared-notifications.yml    # in-pipeline Slack notifier (bot token, chat.postMessage)
│   └── ...
├── templates/                    # Copy these to your repo — see "Templates by stack"
│   ├── java-*.yml                #   validate · develop-deploy · main-deploy · tag-deploy
│   ├── krakend-*.yml
│   ├── nginx-*.yml
│   ├── react-*.yml
│   ├── contracts-*.yml
│   └── shared-*.yml              #   build-publish-image · cleanup-packages
├── .github/ruleset/              # Rulesets as source files (import to GitHub) + their README
├── jenkins/                      # Pre-GitHub-Actions Jenkins stack, kept for reference
│   ├── pipelines/                #   java · react · krakend shared libraries (.groovy)
│   ├── templates/                #   Jenkinsfile per stack
│   ├── casc/                     #   configuration-as-code
│   └── docker-compose.yml
├── scripts/                      # clone-environments.sh · ssh-deploy-debug.sh
├── commitlint.config.js          # This repository's own commit linting
└── README.md
```

A consumer does **not** need to copy `commitlint.config.js`. `shared-commit-lint.yml` looks
for eleven config filenames in the calling repository and, finding none, writes
`extends: ['@commitlint/config-conventional']` for the duration of the job. Add a config
only to depart from conventional commits.

## Contracts (Hardhat/Solidity) Stack

GitFlow flow — image is pushed to ECR only, no EC2/EKS deploy. Downstream consumers pull the image as needed (e.g., a long-lived `eth-dev-node` container started via docker-compose for integration tests).

```
feature/*              ──► compile + size check
     │
     ▼ (PR to develop)      commit-lint + compile + size + test + coverage + gas reporter
     │                       (+ SDK, e2e and static analysis where enabled)
     │
     ▼ (merge to develop)   compile + test
     │
     ▼ (merge to main)      compile + test + artifact (ECR) + deploy (EC2 via VPN) + tag
```

Jobs behind the pipeline:

| Reusable workflow | Runs |
|---|---|
| `contracts-build.yml` | `hardhat compile`, optional size check, uploads artifacts |
| `contracts-test.yml` | Contract tests, optional coverage and gas reporter |
| `contracts-sdk-test.yml` | Builds and tests a client SDK shipped from the same repo |
| `contracts-e2e.yml` | Starts a local chain, deploys, runs the end-to-end suite |
| `contracts-analysis.yml` | solhint + slither |

### Contracts-specific inputs

| Input | Description | Default |
|-------|-------------|---------|
| `container_image` | Run the Node jobs in this image instead of `actions/setup-node` (e.g. `ghcr.io/codehunters-io/ci-base-images:1.0.0-node`) | `''` |
| `node_version` | Node.js version (ignored when `container_image` is set) | `'20'` |
| `package_manager` | `npm`, `yarn`, or `pnpm` | `'pnpm'` |
| `pnpm_version` | pnpm version (when `package_manager: pnpm`) | `'10'` |
| `run_size_check` | Run `hardhat-contract-sizer` (24KB EIP-170 limit) | `true` |
| `test_command` | Command that runs the contract tests (empty = `hardhat test`) | `''` |
| `run_coverage` | Run `solidity-coverage` | `false` |
| `coverage_command` | Command that produces **and may gate** coverage; a non-zero exit fails the job | `''` |
| `coverage_threshold` | Minimum **line** coverage checked by the pipeline itself (0 = disabled) | `0` |
| `run_gas_reporter` | Enable `hardhat-gas-reporter` | `false` |
| `upload_reports` | Upload coverage + gas reports as artifacts | `false` |
| `run_sdk` | Run the SDK build + test job | `false` |
| `sdk_build_command` / `sdk_test_command` | Commands for that job | `''` |
| `run_e2e` | Run the end-to-end job against a local chain | `false` |
| `e2e_node_command` / `e2e_deploy_command` / `e2e_command` | Commands for that job | `npx hardhat node` / `''` / `''` |
| `run_analysis` | Run solhint + slither | `false` |
| `solhint_command` | Command that runs solhint (empty = `solhint 'contracts/**/*.sol'`) | `''` |
| `slither_fail_on` | Severity that fails the job: `none`, `low`, `medium`, `high` | `'high'` |
| `push_latest` | Also push `:latest` tag to ECR | `false` |

### Two coverage gates, and which one to use

`coverage_threshold` is checked by the pipeline against **line** coverage read
from `coverage/coverage-summary.json`. It is the quick option and it is often
the wrong one: a repository whose real rule is "branch coverage on
`contracts/core` stays above 95%" cannot express that here, and lines will
happily read 100% while the rule is broken.

Such a repository already owns a script that checks its rule. Pass it as
`coverage_command` — its exit code fails the job, and the same command runs on
a laptop before the push.

### Consuming the base image

Setting `container_image` replaces `actions/setup-node` in every Node job with
a prebuilt image, which pins the toolchain to a tag rather than to whatever the
runner defaults to. That covers `build`, `test`, `sdk` and `e2e` — `build`
included, because it is the job that produces the bytes the others verify. The
slither job ignores it: `crytic/slither-action` brings its own image with
python, solc and crytic-compile already matched.

All six contracts templates pass it. `node_version` only applies when it is
empty, and it defaults to `20` so both paths through the pipeline agree with
the `engines: ">=20 <21"` the consumers declare.

The Java stack takes the same input. `java-build`, `java-test`, `java-owasp`,
`java-architecture` and `java-artifact-dependency-github` skip
`actions/setup-java` when it is set and take the JDK from the image:

```yaml
uses: Codehunters-IO/ci-templates/.github/workflows/java-main-pipeline.yml@v1
with:
  container_image: 'ghcr.io/codehunters-io/ci-base-images:1.0.0'
```

Use the `-graalvm` tag for repositories that run `./gradlew nativeCompile`.

Two things to know before turning it on for Java. Gradle still comes from
`./gradlew`, not from the Gradle CLI baked into the image — the wrapper is the
contract, so the image saves the JDK download and nothing more. And
`gradle/actions/setup-gradle` still runs inside the container for its
dependency cache, but `GRADLE_USER_HOME` differs from the runner's, so measure
the first few runs before assuming the cache still helps.

The Docker artifact and deploy jobs stay on the runner in every stack. They
drive the Docker daemon rather than a language toolchain, and nesting that in
a container buys nothing.

The Java templates do not set `container_image`. The plumbing is here, the
switch is one line per template, and no pipeline has run through a container
yet — see the note in the base image repo about cutting `v1.0.0` and making the
GHCR package public first.

### ECR Repository

The ECR repository is created automatically by the pipeline if it does not exist. The repository name equals the GitHub repo name (e.g., `codehunters-blockchain-contracts`). Repos are created with `MUTABLE` tags and scan-on-push enabled.

The AWS IAM principal must have `ecr:DescribeRepositories` and `ecr:CreateRepository` in addition to push permissions.

### Out of scope (deliberate)

- **On-chain deploy** (Sepolia / Polygon / mainnet) is NOT executed from CI. Real-network deploys must run out-of-band via a separate, gated, `workflow_dispatch` job with GitHub Environment approvals and isolated secrets.
- **EC2 / EKS deployment** of the dev-node container is NOT performed by this pipeline; image is published to ECR only.
- **ABI / TypeChain publishing** to downstream consumers is not yet wired (reserved for a future input).

## Environments

Each consuming repo must declare the GitHub Environments its own stack references
(**Settings → Environments**). **The names are not the same across stacks** — copying the
Java list into a React repo produces a pipeline that binds to environments that do not
exist, and the secrets resolve to empty rather than failing loudly:

| Stack | `develop` push | `release/*` push | `main` push | Manual promotion |
|---|---|---|---|---|
| Java | `develop` | — | `cert` | `prod` |
| KrakenD | `develop` | — | `cert` | `prod` |
| React | `develop` | `staging` | `production` | — |
| NGINX | `develop` | `staging` | `production` | — |
| Contracts | — | `staging` | `production` | — |

| Environment | Protection |
|-------------|------------|
| `develop` | none |
| `staging` | optional |
| `cert` | optional |
| `production` | recommended: required reviewers — it is the last stop on those three stacks |
| `prod` | **required reviewers** (the gate) |

Two consequences worth stating plainly. On Java and KrakenD, `main` reaches `cert` and
production is a separate, approval-gated `workflow_dispatch` — so a merge to `main` is
safe by construction. On React, NGINX and Contracts there is no such step: **merging to
`main` deploys to `production`**, and the only thing standing between a merge and
production traffic is whatever protection you put on the `production` Environment. If that
list of required reviewers is empty, there is no gate.

> On Java and KrakenD, `release/vX.Y.Z` branches do not map to an environment — they only
> carry the (manual) PR to `main`. On the other three stacks they deploy to `staging`.

- The deploy jobs bind `environment: <name>` at job level, so GitHub Environment protection rules
  (required reviewers, wait timers) apply automatically — no workflow code change.
- **Production promotion is manual + approval-gated**: run the `Release to Production` workflow
  (Actions → *Run workflow*) **from `main`** with a `version` (`vX.Y.Z`). The `prod` Environment's
  required reviewers approve the deploy; the git tag + GitHub Release are created **only after** the
  approved deploy succeeds. The reviewer **is** the gate — configure it (an empty reviewer list = no gate).
- Each repo must declare `develop` / `cert` / `prod` Environments with their **own** `AWS_*` / `AWS_EC2_*`
  / `WG_*` secrets (values differ per environment). Use `scripts/clone-environments.sh` to provision
  `cert` / `prod` from `develop`.
- `spring_profiles` is for **additional** Spring profiles only; the pipeline concatenates them with the
  environment as `SPRING_PROFILES_ACTIVE=<spring_profiles>,<environment>`. Do not set it equal to the env.

## Rulesets

Org-level rulesets live in [`.github/ruleset/`](.github/ruleset/). They are **source files** — apply
them to the org via the GitHub UI (Settings → Rules → Rulesets → Import) or the API; editing the JSON
does not change live rules until imported.

| Ruleset | Target | Scope | Enforces |
|---------|--------|-------|----------|
| `ruleset-develop.json` | branch `develop` | `codehunters-ms-*`, `codehunters-sdk-*` | PR-only, 2 approvals, linear, squash, check `validate / PR Quality Gates` |
| `ruleset-main.json` | branch `main` | `codehunters-ms-*`, `codehunters-sdk-*` | same as develop |
| `ruleset-krakend.json` | branches `develop`+`main` | `codehunters-gw-*` | same, but check `validate / Test & Audit` (KrakenD pipeline) |
| `ruleset-tags.json` | tag `v*.*.*` | `codehunters-ms-*`, `codehunters-sdk-*`, `codehunters-gw-*` | immutable tags (creation/deletion/update/non-fast-forward) |
| `ruleset-ci-templates-develop.json` | branch `develop` | this repository | PR-only, squash |
| `ruleset-ci-templates-main.json` | branch `main` | this repository | PR-only, merge commit |

The last two protect `ci-templates` itself rather than the consuming repositories, and they
are the reason the merge method differs by branch here: `develop` squashes, `main` takes a
merge commit. This repository has no back-merge — `main` accumulates merge commits that
`develop` never sees, which is expected and not drift.

- **Bypass:** repo admins (RepositoryRole 5) and **GitHub Actions** (Integration `15368`) bypass the tag
  rules — the latter lets the `Release to Production` workflow create the `vX.Y.Z` tag.
- KrakenD needs a **separate** ruleset because its PR check name differs from the Java pipeline.
- Roll out in `evaluate` first → run once to confirm the exact required-check context → switch to `active`
  (enabling an `active` ruleset whose check never reports = a merge deadlock).

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/clone-environments.sh` | Provision `cert`/`prod` Environments per repo: clones **variables** from `develop` and sets **secrets** from per-env `.env` files you fill (secret values are not readable, so they are never copied blindly). Run `--template` first to generate the secret-name files. |
| `scripts/ssh-deploy-debug.sh` | Reproduce the EC2 SSH deploy stages locally (connectivity, ECR login, image pull, network/volume) to isolate a deploy failure. The first failing stage is the cause. |

## Container images

`shared-build-publish-image.yml` builds a set of images, smoke-tests each one,
fails on fixable CVEs, and pushes multi-arch manifests carrying an SBOM and
provenance. Copy `templates/shared-build-publish-image.yml` and edit the
`images` array — one object per Dockerfile.

This used to live inline in `ci-base-images`. Publishing a container image is
not something one repository does; it is what every repository that ships a
service does. Leaving the scanning, the SBOM and the tagging rules in one repo
meant the next one started from `docker buildx build --push` and got none of it.

| Input | Description | Default |
|-------|-------------|---------|
| `images` | JSON array of image definitions | required |
| `registry` | Container registry | `ghcr.io` |
| `image_name` | Image repository | calling repo, lowercased |
| `platforms` | Platforms for the published manifest | `linux/amd64,linux/arm64` |
| `smoke_command` | Run against each built image; `IMAGE` is exported to it | none |
| `trivyignores` | Trivy ignore file | none |
| `ignore_policy` | Trivy Rego ignore policy | none |
| `push` | Push the manifest; `false` builds and scans only | `true` |
| `push_rolling` | Move rolling tags off the default branch | `false` |

Per image: `name`, `dockerfile`, and optionally `context`, `tag_suffix`,
`rolling_tag`, `scan_severity`, `smoke_env`.

**`scan_severity` is per image on purpose.** A runtime image faces traffic, so a
fixable HIGH in it is a defect. An image that is root with a full toolchain by
design and lives for the length of one ephemeral job is held to CRITICAL only —
gating it on HIGH blocks every pull request on `gcc` and `git` advisories nobody
can act on, and a gate that is always red is a gate everybody learns to click
past. Unfixed advisories are excluded either way: without an upstream patch
there is nothing the calling repository can do.

The caller must declare `packages: write` and `security-events: write`. A
reusable workflow cannot grant itself more than its caller has, so omitting the
second one silently loses the code scanning upload rather than failing.

`selftest-build-publish-image.yml` builds a fixture through this workflow with
`push: false` on every pull request that touches it, so it is not YAML that
first runs in somebody else's repository.

## Validating images before the merge

`shared-validate-image-pr.yml` is the pre-merge half of the workflow above. It
lints every Dockerfile, optionally lints the repository's shell scripts, runs
one repository-specific gate, then builds and smoke-tests each image on each
architecture and fails on fixable CVEs. It has no publishing path at all.

| Input | Description | Default |
|-------|-------------|---------|
| `images` | JSON array of image definitions | required |
| `platforms` | Architectures to build and smoke-test | `linux/amd64,linux/arm64` |
| `runner_amd64` | Runner for the amd64 jobs | `ubuntu-latest` |
| `runner_arm64` | Runner for the arm64 jobs | `ubuntu-latest` (QEMU) |
| `smoke_command` | Run against each built image; `IMAGE` and `PLATFORM` are exported | none |
| `gate_command` | Repository check, run once on a plain checkout | none |
| `gate_name` | Job name for `gate_command` | `Repository Gate` |
| `hadolint_failure_threshold` | hadolint level that fails the job | `warning` |
| `hadolint_ignore` | hadolint rules to ignore | none |
| `shellcheck_scandir` | Directory to lint; empty skips the job | none |
| `shellcheck_severity` | Lowest severity that fails | `warning` |
| `trivyignores` / `ignore_policy` | As above | none |

Per image: `name`, `dockerfile`, and optionally `context`, `scan_severity`,
`smoke_env`.

**Validate every architecture you publish.** A multi-arch manifest validated on
amd64 only is how an arm64-only break reaches a default branch behind a green
pull request — in `ci-base-images` an `ARG TARGETARCH=amd64` shadowed the value
BuildKit injects, and the arm64 build silently downloaded x86_64 artefacts.
Nothing but an arm64 build catches that.

**`runner_arm64` is why this workflow does not simply reuse the publish one.**
That workflow is a single job per image, and a job has one runner, so its arm64
build is always QEMU. Here the architecture is a matrix dimension, so a caller
with access to native arm64 runners — free on public repositories — can pass
`ubuntu-24.04-arm` and keep the check fast enough that people wait for it. The
default stays QEMU, which works everywhere.

**`gate_command` is deliberately opaque.** It runs on a plain checkout from the
repository root with no image in scope, and what it asserts is the caller's
business: a digest-pin auditor, a codegen drift check, a licence header sweep.
Pushing those into this workflow would mean growing an input per repository.

`selftest-validate-image-pr.yml` runs the whole thing against a fixture on every
pull request that touches it.

## Rescanning images after they are published

`shared-scan-published-images.yml` scans the tags consumers actually pull, on a
schedule, and uploads the findings to code scanning.

The pull request gate and the publish gate both check an image at the moment it
is built — the one moment it is least likely to be vulnerable. Advisories land
against packages that already shipped, so an image that passed every gate is
quietly wrong three weeks later and nothing in the pipeline says so.

| Input | Description | Default |
|-------|-------------|---------|
| `images` | JSON array of image definitions | required |
| `version` | Semver to scan; empty scans the rolling tags | none |
| `registry` | Container registry | `ghcr.io` |
| `image_name` | Image repository | calling repo, lowercased |
| `trivyignores` / `ignore_policy` | As above | none |

Per image: `name`, plus `rolling_tag` and/or `tag_suffix`, and optionally
`scan_severity`.

**A `version` older than an image fails on that image**, because the tag was
never published — a repository that added a variant in 1.2.0 cannot scan it at
1.1.0. The scheduled run passes no version and scans the rolling tags, which is
the case that matters.

This one has no self-test: it scans a published tag, and the fixture the other
self-tests build is never published. It is exercised by its consumers instead.

## Package cleanup

`shared-cleanup-packages.yml` prunes **untagged** versions from a GHCR container
package. Copy `templates/shared-cleanup-packages.yml` into the publishing repo;
it defaults to that repo's own name, so most need no edits.

Untagged versions are what a registry accumulates by itself. Every time a tag
moves to a new digest the old manifest stays behind — unreferenced, unreachable
through any tag, and invisible unless you count. Buildx attestations add more.
`ci-base-images` reached 150 versions in five days, 124 of them untagged: 83%
of the registry was garbage nothing could pull.

| Input | Description | Default |
|-------|-------------|---------|
| `package_name` | Container package name | repository name |
| `owner` | Org or user owning the package | repository owner |
| `min_versions_to_keep` | Untagged versions retained, newest first | `10` |
| `dry_run` | Only report | `true` |

**A tagged version is never a candidate.** That comes from
`delete-only-untagged-versions` in the underlying action, not from a filter
written here — semver tags, rolling tags and `sha-` tags are safe by
construction rather than by a regex that could be wrong. A retention window is
kept on top of that, because the most recent untagged manifests are the ones a
half-finished multi-arch push leaves behind.

The `plan` job runs first and always. It prints the counts and the surviving
tags to the step summary, so the deletion is reviewable before it happens. The
scheduled run only ever plans; deleting means dispatching the workflow by hand
with `dry_run` unchecked.

## Requirements on the EC2 host

- Docker + Docker Compose V2
- AWS CLI (for ECR login)
- External Docker network `codehunters_net` and volume `shared_logs` (auto-created if missing)
- SSH access for the configured `AWS_EC2_USER`

## License

MIT

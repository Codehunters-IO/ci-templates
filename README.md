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

1. Copy the templates for your stack from `templates/` into your repo's `.github/workflows/`:
   ```bash
   cp templates/java-feature-build.yml   .github/workflows/
   cp templates/java-pr-develop.yml      .github/workflows/
   cp templates/java-develop-deploy.yml  .github/workflows/   # develop → develop (+ auto release branch)
   cp templates/java-main-deploy.yml     .github/workflows/   # main → cert
   cp templates/java-tag-deploy.yml      .github/workflows/   # prod (manual: workflow_dispatch from main)
   ```

2. Replace `<org>` with your GitHub organization in each template:
   ```yaml
   uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
   ```

3. Configure the required secrets (see below).

## Versioning

Templates pin a release, not a branch:

```yaml
uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@v1
```

`v1` is a floating alias that moves to the newest `v1.x.y`. Pinning it means a
consumer picks up fixes and backward-compatible additions without editing its
workflows, and never picks up a breaking change unannounced. Pin `@v1.4.2`
instead when a pipeline must not move at all, and `@main` only to test an
unreleased change on purpose.

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
├── templates/                    # Copy these to your repo
│   ├── java-*.yml                #   develop-deploy · main-deploy · tag-deploy (workflow_dispatch)
│   ├── krakend-*.yml
│   ├── contracts-*.yml
│   └── react-*.yml
├── .github/ruleset/              # Org rulesets (import to GitHub): develop · main · krakend · tags
├── scripts/                      # clone-environments.sh · ssh-deploy-debug.sh
└── README.md
```

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

Each consuming repo must declare these GitHub Environments (**Settings → Environments**):

| Environment | Reached by | Protection |
|-------------|-----------|------------|
| `develop` | push to `develop` | none |
| `cert` | push to `main` | optional |
| `prod` | `Release to Production` workflow (`workflow_dispatch` from `main`) | **required reviewers** (the gate) |

> `release/vX.Y.Z` branches do not map to an environment — they only carry the (manual) PR to `main`.

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

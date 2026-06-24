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
     │                              → auto-create branch release/vX.Y.Z (semver)   ← no PR, no deploy
     │                       └── uses java-main-pipeline.yml
     │
     ▼ (release/vX.Y.Z)     open a PR to main manually (stabilization branch — no deploy)
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
> commit messages). It does **not** deploy and **no PR is opened automatically** — open the PR to
> `main` manually when ready. Merging it to `main` deploys to `cert`.
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
   uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@main
   ```

3. Configure the required secrets (see below).

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
    uses: <org>/ci-templates/.github/workflows/java-main-pipeline.yml@main
    with:
      run_build: true
      run_test: true
      run_artifact: true
      run_deploy: true
      deploy_target: 'ec2-vpn'   # ec2 | ec2-vpn | eks
      environment: 'develop'
    secrets: inherit
```

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

### Notifications (`run_notifications: true`)

Supports multiple providers via `notify_providers` (comma-separated). Default: `slack`.

| Provider | Secrets Required | Notes |
|----------|-----------------|-------|
| `slack` | `SLACK_WEBHOOK_URL` | Block Kit message with status, changelog, and action button |
| `teams` | `TEAMS_WEBHOOK_URL` | MessageCard with facts, changelog, and action button |

Notifications include: status, environment, branch, actor, link to the workflow run, and release changelog when available.

| Input | Description | Default |
|-------|-------------|---------|
| `run_notifications` | Enable notifications | `false` |
| `notify_providers` | Providers to use (comma-separated) | `slack` |
| `notify_mention_on_failure` | Mention on failure (e.g., `@channel`) | `''` |

Example — Slack notification:
```yaml
with:
  run_notifications: true
  notify_providers: 'slack'
  notify_mention_on_failure: '@channel'
secrets: inherit
```

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

> The release flow only **creates a branch** (`release/vX.Y.Z`) via `GITHUB_TOKEN` — no PAT is needed
> (the PR to `main` is opened manually). The prod release tag is created by GitHub Actions, which
> bypasses the tag ruleset (see Rulesets below).

## Directory Structure

```
ci-templates/
├── .github/workflows/            # Reusable workflows
│   ├── java-main-pipeline.yml
│   ├── java-pr-pipeline.yml
│   ├── krakend-main-pipeline.yml
│   ├── react-main-pipeline.yml
│   ├── shared-deploy-ec2.yml
│   ├── shared-deploy-ec2-vpn.yml
│   ├── shared-deploy-eks.yml
│   ├── shared-notifications.yml
│   ├── shared-slack-notify.yml
│   └── ...
├── templates/                    # Copy these to your repo
│   ├── java-*.yml                #   develop-deploy · main-deploy · tag-deploy (workflow_dispatch)
│   ├── krakend-*.yml
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
     │
     ▼ (merge to develop)   compile + test
     │
     ▼ (merge to main)      compile + test + artifact (ECR) + deploy (EC2 via VPN) + tag
```

### Contracts-specific inputs

| Input | Description | Default |
|-------|-------------|---------|
| `node_version` | Node.js version | `'24'` |
| `package_manager` | `npm`, `yarn`, or `pnpm` | `'pnpm'` |
| `pnpm_version` | pnpm version (when `package_manager: pnpm`) | `'10'` |
| `run_size_check` | Run `hardhat-contract-sizer` (24KB EIP-170 limit) | `true` |
| `run_coverage` | Run `solidity-coverage` | `false` |
| `coverage_threshold` | Minimum line coverage (0-100, 0 = disabled) | `0` |
| `run_gas_reporter` | Enable `hardhat-gas-reporter` | `false` |
| `upload_reports` | Upload coverage + gas reports as artifacts | `false` |
| `push_latest` | Also push `:latest` tag to ECR | `false` |

### ECR Repository

The ECR repository is created automatically by the pipeline if it does not exist. The repository name equals the GitHub repo name (e.g., `vitxo-blockchain-contracts`). Repos are created with `MUTABLE` tags and scan-on-push enabled.

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
| `ruleset-develop.json` | branch `develop` | `vitxo-ms-*`, `vitxo-sdk-*` | PR-only, 2 approvals, linear, squash, check `validate / PR Quality Gates` |
| `ruleset-main.json` | branch `main` | `vitxo-ms-*`, `vitxo-sdk-*` | same as develop |
| `ruleset-krakend.json` | branches `develop`+`main` | `vitxo-gw-*` | same, but check `validate / Test & Audit` (KrakenD pipeline) |
| `ruleset-tags.json` | tag `v*.*.*` | `vitxo-ms-*`, `vitxo-sdk-*`, `vitxo-gw-*` | immutable tags (creation/deletion/update/non-fast-forward) |

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

## Requirements on the EC2 host

- Docker + Docker Compose V2
- AWS CLI (for ECR login)
- External Docker network `soldife_net` and volume `shared_logs` (auto-created if missing)
- SSH access for the configured `AWS_EC2_USER`

## License

MIT

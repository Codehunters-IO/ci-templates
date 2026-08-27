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
     ▼ (PR to develop)      build → test → coverage → sonar → owasp → architecture
     │                       └── uses java-pr-pipeline.yml (quality gates only)
     │
     ▼ (merge to develop)   build → test → coverage → sonar → owasp → architecture
     │                              → artifact (ECR) → deploy (DEV) → cleanup → release PR
     │                       └── uses java-main-pipeline.yml
     │
     ▼ (release/*)          build → test → artifact (ECR) → deploy (STAGING)
     │
     ▼ (merge to main)      build → artifact (ECR) → deploy (PRODUCTION)
```

## Quick Start

1. Copy the templates for your stack from `templates/` into your repo's `.github/workflows/`:
   ```bash
   cp templates/java-feature-build.yml   .github/workflows/
   cp templates/java-pr-develop.yml      .github/workflows/
   cp templates/java-develop-deploy.yml  .github/workflows/
   cp templates/java-release-deploy.yml  .github/workflows/
   cp templates/java-main-deploy.yml     .github/workflows/
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
| `AWS_ECR_URL` | ECR registry URL (e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com`) |

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
│   ├── shared-notifications.yml
│   ├── shared-slack-notify.yml
│   └── ...
├── templates/                    # Copy these to your repo
│   ├── java-*.yml
│   ├── krakend-*.yml
│   ├── contracts-*.yml
│   └── react-*.yml
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
| `node_version` | Node.js version (ignored when `container_image` is set) | `'22'` |
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
runner defaults to. The slither job ignores it: `crytic/slither-action` brings
its own image with python, solc and crytic-compile already matched.

### ECR Repository

The ECR repository is created automatically by the pipeline if it does not exist. The repository name equals the GitHub repo name (e.g., `codehunters-blockchain-contracts`). Repos are created with `MUTABLE` tags and scan-on-push enabled.

The AWS IAM principal must have `ecr:DescribeRepositories` and `ecr:CreateRepository` in addition to push permissions.

### Out of scope (deliberate)

- **On-chain deploy** (Sepolia / Polygon / mainnet) is NOT executed from CI. Real-network deploys must run out-of-band via a separate, gated, `workflow_dispatch` job with GitHub Environment approvals and isolated secrets.
- **EC2 / EKS deployment** of the dev-node container is NOT performed by this pipeline; image is published to ECR only.
- **ABI / TypeChain publishing** to downstream consumers is not yet wired (reserved for a future input).

## Requirements on the EC2 host

- Docker + Docker Compose V2
- AWS CLI (for ECR login)
- External Docker network `codehunters_net` and volume `shared_logs` (auto-created if missing)
- SSH access for the configured `AWS_EC2_USER`

## License

MIT

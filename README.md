# CI Templates

Reusable GitHub Actions workflows for Java, Krakend and React projects following a GitFlow branching strategy.

## Stacks

| Stack | Main pipeline | Templates |
|-------|--------------|-----------|
| Java (Spring Boot) | `.github/workflows/java-main-pipeline.yml` | `templates/java-*.yml` |
| Krakend | `.github/workflows/krakend-main-pipeline.yml` | `templates/krakend-*.yml` |
| React | `.github/workflows/react-main-pipeline.yml` | `templates/react-*.yml` |

## GitFlow

```
feature/* ──► build
     │
     ▼ (PR to develop)      build → test → sonar/qodana → owasp → architecture
     │
     ▼ (merge to develop)   build → test → artifact (ECR) → deploy (DEV) → release PR
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

| Secret | Description |
|--------|-------------|
| `WIREGUARD_CONFIG` | Full contents of the WireGuard `.conf` file (`[Interface]` + `[Peer]` blocks). The runner writes it to `/etc/wireguard/wg0.conf` and runs `wg-quick up wg0`. |

### SonarQube (`code_analysis: 'sonar'`)

| Secret | Description |
|--------|-------------|
| `SONAR_HOST_URL` | SonarQube server URL |
| `SONAR_TOKEN` | SonarQube authentication token |

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
│   ├── krakend-main-pipeline.yml
│   ├── react-main-pipeline.yml
│   ├── shared-deploy-ec2.yml
│   ├── shared-deploy-ec2-vpn.yml
│   ├── shared-deploy-eks.yml
│   └── ...
├── templates/                    # Copy these to your repo
│   ├── java-*.yml
│   ├── krakend-*.yml
│   └── react-*.yml
└── README.md
```

## Requirements on the EC2 host

- Docker + Docker Compose V2
- AWS CLI (for ECR login)
- External Docker network `soldife_net` and volume `shared_logs` (auto-created if missing)
- SSH access for the configured `AWS_EC2_USER`

## License

MIT

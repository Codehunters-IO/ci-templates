# CI Templates for Java Projects

Reusable GitHub Actions workflows for Java projects following GitFlow branching strategy.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GITFLOW CI/CD                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  feature/* ──┬──► [build]                                               │
│  bugfix/*  ──┘                                                          │
│       │                                                                 │
│       ▼ (PR to develop)                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ build → test → sonar                                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼ (merge to develop)                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ build → test → semver → artifact (ECR) → deploy (DEV)            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼ (create release/*)                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ build → test → artifact (ECR) → deploy (STAGING)                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼ (merge to main)                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ build → artifact (ECR) → deploy (PRODUCTION)                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Copy Templates

Copy the templates from `/templates/` to your repository's `.github/workflows/`:

```bash
# Feature/Bugfix build
cp templates/java-feature-build.yml .github/workflows/

# PR validation
cp templates/java-pr-develop.yml .github/workflows/

# Deploy to DEV (develop branch)
cp templates/java-develop-deploy.yml .github/workflows/

# Deploy to STAGING (release branches)
cp templates/java-release-deploy.yml .github/workflows/

# Deploy to PRODUCTION (main branch)
cp templates/java-main-deploy.yml .github/workflows/
```

### 2. Update Organization Name

Replace `<org>` with your GitHub organization in each template:

```yaml
uses: <org>/ci-templates/.github/workflows/main-pipeline-backend.yml@main
# Change to:
uses: your-org/ci-templates/.github/workflows/main-pipeline-backend.yml@main
```

### 3. Configure Secrets

See [Configuration Guide](docs/CONFIGURATION.md) for required secrets.

## Reusable Workflows

| Workflow | Purpose |
|----------|---------|
| `main-pipeline-backend.yml` | Main orchestrator - controls all steps |
| `java-build.yml` | Gradle build + Spotless check |
| `java-test.yml` | Run tests |
| `java-semver.yml` | Semantic versioning + CHANGELOG |
| `java-sonarqube.yml` | SonarQube analysis |
| `java-artifact-ecr.yml` | Build Docker + push to ECR |
| `java-deploy-ec2.yml` | Deploy to EC2 via SSH |

## Main Pipeline Inputs

```yaml
uses: org/ci-templates/.github/workflows/main-pipeline-backend.yml@main
with:
  # Java configuration
  java_version: '21'           # Java version (default: 21)
  java_distribution: 'temurin' # JDK distribution (default: temurin)

  # Pipeline steps
  run_build: true              # Run build (default: true)
  run_test: false              # Run tests (default: false)
  run_sonar: false             # Run SonarQube (default: false)
  run_semver: false            # Calculate version (default: false)
  run_artifact: false          # Build/push Docker (default: false)
  run_deploy: false            # Deploy to EC2 (default: false)

  # Semver options
  update_changelog: false      # Update CHANGELOG.md (default: false)

  # Deploy options
  spring_profile: 'production' # Spring profile (default: production)
  health_check_path: ''        # Health check endpoint (default: empty)
```

## Pipeline Outputs

```yaml
outputs:
  version:      # Semantic version (e.g., 1.2.3)
  version_tag:  # Version tag (e.g., v1.2.3)
  image_tag:    # Docker image tag pushed to ECR
```

## Semantic Versioning

Commit message patterns:

| Pattern | Version Bump | Example |
|---------|--------------|---------|
| `MAJOR:` or `BREAKING CHANGE:` | Major | `MAJOR: remove deprecated API` |
| `feat:` | Minor | `feat: add user authentication` |
| (any other) | Patch | `fix: resolve null pointer` |

## Directory Structure

```
ci-templates/
├── .github/workflows/           # Reusable workflows
│   ├── main-pipeline-backend.yml
│   ├── java-build.yml
│   ├── java-test.yml
│   ├── java-semver.yml
│   ├── java-sonarqube.yml
│   ├── java-artifact-ecr.yml
│   └── java-deploy-ec2.yml
├── templates/                   # Copy these to your repo
│   ├── java-feature-build.yml
│   ├── java-pr-develop.yml
│   ├── java-develop-deploy.yml
│   ├── java-release-deploy.yml
│   └── java-main-deploy.yml
├── docs/
│   └── CONFIGURATION.md
└── README.md
```

## Requirements

### EC2 Server

- Docker
- Docker Compose V2
- AWS CLI
- SSH access configured

### Repository

- Dockerfile in root
- Gradle wrapper (`gradlew`)
- Spring Boot application (for default profiles)

## License

MIT

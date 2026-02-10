# Java Deploy to AWS EC2 Workflows

This repository contains GitHub Actions workflows for deploying Java applications to AWS EC2 using Docker containers stored in AWS ECR.

## Workflows

### 1. `java-deploy-develop.yml`
Main workflow that triggers on pushes to the `develop` branch. It orchestrates the complete CI/CD pipeline:
- Builds the Java application
- Runs tests
- Generates semantic version
- Builds and pushes Docker image to AWS ECR
- Deploys the application to AWS EC2

### 2. `java-artifact-ecr.yml` (Reusable)
Builds the Docker image and optionally pushes it to AWS ECR.

**Inputs:**
- `runner` (optional): Type of GitHub runner (default: `ubuntu-latest`)
- `version` (optional): Docker image version tag
- `push_to_ecr` (optional): Whether to push to ECR (default: `false`)

**Outputs:**
- `image_tag`: The Docker image tag used

### 3. `java-deploy-ec2.yml` (Reusable)
Deploys the Docker image from ECR to an AWS EC2 instance.

**Inputs:**
- `runner` (optional): Type of GitHub runner (default: `ubuntu-latest`)
- `version` (required): Version/tag of the Docker image to deploy

## Required Secrets

Configure the following secrets in your GitHub repository settings:

### AWS Configuration
- `AWS_ROLE_TO_ASSUME`: ARN of the AWS IAM role to assume for deployment
- `AWS_REGION`: AWS region where your ECR and EC2 are located (e.g., `us-east-1`)
- `ECR_REPOSITORY`: Name of the ECR repository (e.g., `my-app`)

### EC2 Configuration
- `EC2_HOST`: Hostname or IP address of the EC2 instance
- `EC2_USER`: SSH username for the EC2 instance (e.g., `ec2-user`, `ubuntu`)
- `EC2_SSH_KEY`: Private SSH key for accessing the EC2 instance

### Application Configuration
- `APP_NAME`: Name of your application (used for container and directory naming)
- `APP_PORT`: Port on which to expose the application (e.g., `8080`)

## Deployment Structure

The workflow creates the following structure on the EC2 instance:

```
/opt/docker/
└── <APP_NAME>/
    ├── docker-compose.yml   # Docker Compose configuration
    ├── start.sh             # Script to start the container
    └── stop.sh              # Script to stop the container
```

### docker-compose.yml
Defines the Docker service configuration:
- Uses the image from ECR with the specified version tag
- Maps the configured port to container port 8080
- Sets Spring profile to `production`
- Configures log rotation (10MB max size, 3 files)

### start.sh
Script that:
1. Pulls the latest image from ECR
2. Starts the container in detached mode
3. Shows the container status

### stop.sh
Script that:
1. Stops and removes the container
2. Cleans up Docker resources

## AWS IAM Permissions

The IAM role specified in `AWS_ROLE_TO_ASSUME` needs the following permissions:

### ECR Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```

## EC2 Instance Prerequisites

The EC2 instance must have:
1. **Docker** installed and running
2. **Docker Compose** installed
3. **AWS CLI** installed and configured
4. Proper **IAM instance profile** or credentials to pull from ECR
5. SSH access configured with the provided key

## Usage Example

### Using the main workflow
Simply merge your changes to the `develop` branch:
```bash
git checkout develop
git merge feature/my-feature
git push origin develop
```

### Using reusable workflows in your own pipeline
```yaml
name: My Custom Pipeline

on:
  push:
    branches:
      - develop

jobs:
  build-and-push:
    uses: soldife/ci-templates/.github/workflows/java-artifact-ecr.yml@main
    with:
      version: "1.2.3"
      push_to_ecr: true
    secrets: inherit

  deploy:
    needs: build-and-push
    uses: soldife/ci-templates/.github/workflows/java-deploy-ec2.yml@main
    with:
      version: "1.2.3"
    secrets: inherit
```

## Deployment Process

1. **Build Phase**: Builds the Java application using Gradle
2. **Test Phase**: Runs the test suite
3. **Versioning**: Generates semantic version based on commit messages
4. **Artifact**: 
   - Builds Docker image
   - Tags with semantic version and `latest`
   - Pushes to AWS ECR
5. **Deploy**:
   - Connects to EC2 via SSH
   - Creates deployment directory structure
   - Generates docker-compose.yml with ECR image reference
   - Creates start.sh and stop.sh scripts
   - Stops existing container (if running)
   - Pulls new image from ECR
   - Starts new container

## Troubleshooting

### SSH Connection Issues
- Verify `EC2_SSH_KEY` is correctly formatted (include `-----BEGIN RSA PRIVATE KEY-----` headers)
- Check that the security group allows SSH from GitHub Actions IP ranges
- Verify `EC2_HOST` and `EC2_USER` are correct

### ECR Authentication Issues
- Ensure the IAM role has proper ECR permissions
- Verify `AWS_REGION` matches your ECR repository region
- Check that OIDC provider is configured for GitHub Actions

### Container Start Issues
- Check EC2 instance has enough resources (CPU, memory, disk)
- Verify the application port is not already in use
- Review container logs: `docker logs <APP_NAME>`

## Semantic Versioning

The workflow uses conventional commits for versioning:
- Commits with `MAJOR` or `BREAKING CHANGE` → major version bump (e.g., 1.0.0 → 2.0.0)
- Commits with `feat` → minor version bump (e.g., 1.0.0 → 1.1.0)  
- Other commits → patch version bump (e.g., 1.0.0 → 1.0.1)

Example commit messages:
```bash
git commit -m "feat: add new API endpoint"           # minor bump → 1.1.0
git commit -m "fix: resolve null pointer error"      # patch bump → 1.0.1
git commit -m "MAJOR: breaking API changes"          # major bump → 2.0.0
git commit -m "feat: BREAKING CHANGE: new API"       # major bump → 2.0.0
```

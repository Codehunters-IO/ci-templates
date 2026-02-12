# Configuration Guide

## Repository Variables (vars.*)

Configure these in your repository settings: **Settings → Secrets and variables → Actions → Variables**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `JAVA_VERSION` | Java version to use | `21` | No |
| `JAVA_DISTRIBUTION` | JDK distribution | `temurin` | No |
| `RUNNER` | GitHub Actions runner | `ubuntu-latest` | No |

## Repository Secrets (secrets.*)

Configure these in your repository settings: **Settings → Secrets and variables → Actions → Secrets**

### AWS Secrets (Required for ECR/EC2)

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_ROLE_TO_ASSUME` | ARN of IAM role for OIDC auth | `arn:aws:iam::123456789:role/GitHubActions` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `ECR_REPOSITORY` | ECR repository name | `my-app` |

### EC2 Deployment Secrets (Required for deploy)

| Secret | Description | Example |
|--------|-------------|---------|
| `EC2_HOST` | EC2 instance IP or hostname | `10.0.1.50` |
| `EC2_USER` | SSH username | `ec2-user` or `ubuntu` |
| `EC2_SSH_KEY` | SSH private key (PEM format) | `-----BEGIN RSA...` |
| `APP_NAME` | Application name | `my-microservice` |
| `APP_PORT` | External port to expose | `8081` |

### SonarQube Secrets (Required for sonar)

| Secret | Description | Example |
|--------|-------------|---------|
| `SONAR_HOST_URL` | SonarQube server URL | `https://sonar.example.com` |
| `SONAR_TOKEN` | SonarQube authentication token | `sqp_xxx...` |

## Quick Setup Checklist

### Minimum Setup (Build + Test only)

No secrets required. Just copy the template and update the organization name.

### Full Setup (Build + Test + Deploy)

1. **AWS IAM Role**: Create role with trust policy for GitHub OIDC
2. **ECR Repository**: Create ECR repository for Docker images
3. **EC2 Instance**: Ensure Docker and AWS CLI are installed
4. **SSH Key**: Generate or use existing SSH key for EC2 access
5. **Configure Secrets**: Add all secrets listed above

## AWS OIDC Trust Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/*:*"
        }
      }
    }
  ]
}
```

## IAM Role Permissions

The IAM role needs these permissions:

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

## Environment-Specific Configuration

Use `spring_profile` input to configure different environments:

| Environment | Branch | spring_profile |
|-------------|--------|----------------|
| Development | develop | `develop` |
| Staging | release/* | `staging` |
| Production | main | `production` |

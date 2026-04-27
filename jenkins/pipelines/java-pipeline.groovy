// Java Pipeline: build → test → push ECR → deploy (local)
// Jenkins corre en el mismo servidor, deploy es local via Docker socket

pipeline {
    agent any

    parameters {
        string(name: 'BRANCH', defaultValue: 'develop', description: 'Branch to build')
        string(name: 'JAVA_VERSION', defaultValue: '21', description: 'Java version')
        string(name: 'BUILD_TOOL', defaultValue: 'gradle', description: 'gradle or maven')
        booleanParam(name: 'RUN_TEST', defaultValue: true, description: 'Run tests')
        booleanParam(name: 'RUN_ARTIFACT', defaultValue: true, description: 'Push to ECR')
        booleanParam(name: 'RUN_DEPLOY', defaultValue: true, description: 'Deploy container')
        string(name: 'ENVIRONMENT', defaultValue: 'develop', description: 'Target environment')
        string(name: 'APP_PORT', defaultValue: '8080', description: 'External app port')
        string(name: 'DOCKER_PLATFORM', defaultValue: 'linux/arm64', description: 'Container platform')
        string(name: 'MEMORY_LIMIT', defaultValue: '512m', description: 'Container memory limit')
        string(name: 'MEMORY_RESERVATION', defaultValue: '256m', description: 'Container memory reservation')
        string(name: 'SPRING_PROFILES', defaultValue: '', description: 'Spring profiles (comma-separated)')
        string(name: 'CONTAINER_ENV_VARS', defaultValue: '', description: 'Extra env vars (KEY=VALUE per line)')
    }

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_REGION            = "${env.AWS_REGION}"
        AWS_ECR_URL           = "${env.AWS_ECR_URL}"
        REPO_NAME             = "${env.JOB_NAME.split('/')[0]}"
        IMAGE_TAG             = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
    }

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    tools {
        jdk "jdk-${params.JAVA_VERSION}"
    }

    stages {
        stage('Build') {
            steps {
                script {
                    if (params.BUILD_TOOL == 'gradle') {
                        sh './gradlew clean build -x test --no-daemon --build-cache'
                    } else {
                        sh 'mvn clean package -DskipTests -B'
                    }
                }
            }
        }

        stage('Test') {
            when { expression { params.RUN_TEST } }
            steps {
                script {
                    if (params.BUILD_TOOL == 'gradle') {
                        sh './gradlew test --no-daemon'
                    } else {
                        sh 'mvn test -B'
                    }
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: '**/build/test-results/**/*.xml, **/target/surefire-reports/*.xml'
                }
            }
        }

        stage('Push to ECR') {
            when { expression { params.RUN_ARTIFACT } }
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${AWS_ECR_URL}

                    docker build --platform ${params.DOCKER_PLATFORM} \
                        -t ${AWS_ECR_URL}/${REPO_NAME}:${IMAGE_TAG} .

                    docker push ${AWS_ECR_URL}/${REPO_NAME}:${IMAGE_TAG}
                """
            }
        }

        stage('Deploy') {
            when { expression { params.RUN_DEPLOY } }
            steps {
                deployLocal()
            }
        }
    }

    post {
        success { echo "Pipeline completed successfully - ${REPO_NAME}:${IMAGE_TAG}" }
        failure { echo "Pipeline FAILED - ${REPO_NAME}:${IMAGE_TAG}" }
        always  { cleanWs() }
    }
}

def deployLocal() {
    def deployDir = "/opt/docker/${REPO_NAME}"
    def springProfiles = params.SPRING_PROFILES ?
        "${params.SPRING_PROFILES},${params.ENVIRONMENT}" : params.ENVIRONMENT

    def envBlock = """\
      - APP_NAME=${REPO_NAME}
      - PATH_LOGS=/app/log/${REPO_NAME}
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=${AWS_REGION}
      - SPRING_PROFILES_ACTIVE=${springProfiles}"""

    if (params.CONTAINER_ENV_VARS?.trim()) {
        params.CONTAINER_ENV_VARS.split('\n').each { line ->
            if (line.trim()) envBlock += "\n      - ${line.trim()}"
        }
    }

    def compose = """\
services:
  ${REPO_NAME}:
    image: ${AWS_ECR_URL}/${REPO_NAME}:${IMAGE_TAG}
    platform: ${params.DOCKER_PLATFORM}
    container_name: ${REPO_NAME}
    restart: unless-stopped
    environment:
${envBlock}
    ports:
      - "${params.APP_PORT}:8080"
    volumes:
      - shared_logs:/app/log
    mem_limit: ${params.MEMORY_LIMIT}
    mem_reservation: ${params.MEMORY_RESERVATION}
    networks:
      - soldife_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  shared_logs:
    external: true

networks:
  soldife_net:
    external: true"""

    sh """
        mkdir -p ${deployDir}
        cat > ${deployDir}/docker-compose.yml << 'COMPOSE_EOF'
${compose}
COMPOSE_EOF

        cd ${deployDir}
        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ECR_URL}
        docker pull ${AWS_ECR_URL}/${REPO_NAME}:${IMAGE_TAG}
        docker compose down || true
        docker compose up -d
        docker system prune -af > /dev/null 2>&1 || true
        echo "Deployed ${REPO_NAME}:${IMAGE_TAG} to ${deployDir}"
    """
}

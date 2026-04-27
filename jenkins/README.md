# Jenkins CI - Fallback sin minutos de GitHub Actions

Solución temporal para build, test y deploy a ECR cuando se agotan los minutos de GitHub Actions.
Jenkins corre en el mismo servidor EC2 donde se despliegan las apps.

## Arquitectura

```
EC2 Server (mismo servidor)
├── /opt/docker/jenkins/          ← Jenkins (este compose)
│   ├── docker-compose.yml
│   └── jenkins_home/             ← Volumen persistente
│       ├── casc/jenkins.yaml     ← Config automática
│       └── pipelines/            ← Pipelines compartidos
├── /opt/docker/{app-1}/          ← Apps desplegadas (local, sin SSH)
├── /opt/docker/{app-2}/
└── soldife_net                   ← Red compartida
```

## Setup

### 1. Clonar y preparar

```bash
cd /opt/docker
git clone https://github.com/<org>/ci-templates.git
cd ci-templates/jenkins

cp .env.example .env
nano .env  # configurar credenciales
```

### 2. Levantar Jenkins

```bash
docker compose up -d
docker compose logs -f jenkins
```

### 3. Copiar pipelines al volumen

```bash
docker cp pipelines/. jenkins:/var/jenkins_home/pipelines/
```

### 4. Acceder

- URL: `http://<EC2_IP>:8081`
- Usuario: `admin`
- Password: valor de `JENKINS_ADMIN_PASSWORD` en `.env`

## Crear un Job

1. New Item → Pipeline
2. Pipeline → Definition: **Pipeline script from SCM**
3. SCM: Git → Repository URL del proyecto
4. Branch: `*/develop`
5. Script Path: `Jenkinsfile`

El proyecto necesita un `Jenkinsfile` en su raíz. Copiar de `jenkins/templates/`.

## Pipelines disponibles

| Pipeline | Archivo | Stages |
|----------|---------|--------|
| Java Spring Boot | `pipelines/java-pipeline.groovy` | Build → Test → Push ECR → Deploy |
| KrakenD | `pipelines/krakend-pipeline.groovy` | Build → Validate → Push ECR → Deploy |
| React | `pipelines/react-pipeline.groovy` | Install → Build → Test → Push ECR → Deploy |

## Parámetros

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `BRANCH` | develop | Branch a construir |
| `RUN_TEST` | true | Ejecutar tests |
| `RUN_ARTIFACT` | true | Push imagen a ECR |
| `RUN_DEPLOY` | true | Deploy local del container |
| `ENVIRONMENT` | develop | Ambiente destino |
| `APP_PORT` | 8080 | Puerto externo |
| `DOCKER_PLATFORM` | linux/arm64 | Plataforma del container |
| `MEMORY_LIMIT` | 512m | Límite de memoria |
| `SPRING_PROFILES` | (vacío) | Profiles Spring Boot (solo Java) |

## Deploy local

Como Jenkins corre en el mismo servidor, el deploy:
1. Genera `docker-compose.yml` en `/opt/docker/{app}/`
2. Pull de la imagen desde ECR
3. `docker compose down` + `docker compose up -d`

No necesita SSH, VPN ni credenciales adicionales — usa el Docker socket montado.

## Volúmenes montados en Jenkins

| Mount | Propósito |
|-------|-----------|
| `/var/run/docker.sock` | Docker del host (build + deploy) |
| `/usr/bin/docker` | Docker CLI del host |
| `/usr/local/bin/aws` | AWS CLI del host |
| `/opt/docker` | Directorio de deploy de apps |

## Mantenimiento

```bash
# Reiniciar
docker compose restart

# Backup
docker run --rm -v jenkins_home:/data -v $(pwd):/backup \
    alpine tar czf /backup/jenkins-backup.tar.gz /data

# Actualizar pipelines
docker cp pipelines/. jenkins:/var/jenkins_home/pipelines/
```

## Diferencias con GitHub Actions

| Aspecto | GitHub Actions | Jenkins (fallback) |
|---------|---------------|-------------------|
| Trigger | Automático (push/PR) | Manual |
| Sonar/Coverage | Incluido | No |
| Release PR | Automático | No |
| Notifications | Slack/Teams | No |
| Deploy | SSH remoto | Local (mismo server) |

> **Nota**: Jenkins es fallback temporal. Al renovar minutos de GitHub Actions, volver a los workflows principales.

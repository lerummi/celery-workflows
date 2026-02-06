# celery-workflows

A production-ready distributed workflow system built with Celery, FastAPI, and Kubernetes. This project provides a scalable task queue infrastructure for executing complex workflows with real-time monitoring, persistent storage, and disaster recovery capabilities.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Workflow Development](#workflow-development)
- [Monitoring](#monitoring)
- [Backup and Restore](#backup-and-restore)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [Makefile Reference](#makefile-reference)

## Overview

This project implements a distributed task queue system using Celery with Kubernetes orchestration. It combines multiple technologies to provide a complete workflow execution platform:

- **Celery** - Distributed task queue for asynchronous workflow execution
- **Redis** - Message broker and result backend
- **FastAPI** - REST API for workflow management and status monitoring
- **Flower** - Real-time monitoring dashboard for Celery tasks
- **SeaweedFS** - Distributed object storage with S3-compatible API
- **Velero** - Backup and disaster recovery with CSI volume snapshots
- **Longhorn** - Distributed block storage for production deployments

The system is designed to handle complex workflow chains where tasks depend on the results of previous tasks, with automatic retry logic, persistent storage, and comprehensive monitoring.

## Features

### Core Capabilities

- **Task Chaining** - Define multi-step workflows with automatic result passing
- **Distributed Execution** - Scale workers horizontally across multiple pods
- **Persistent Results** - Store task results in Redis with configurable retention
- **Automatic Retries** - Configurable retry logic for failed tasks
- **S3 Storage Integration** - Save workflow results to SeaweedFS object storage
- **REST API** - Trigger workflows and check status via HTTP endpoints
- **Real-time Monitoring** - Track task execution in the Flower dashboard

### Operational Features

- **High Availability** - StatefulSet-based Redis with persistent storage
- **Disaster Recovery** - Full backup/restore with Velero and CSI snapshots
- **Resource Management** - Configurable CPU/memory limits per component
- **Auto-discovery** - Automatically discovers task modules in `src/tasks/`
- **Production-ready** - Helm chart with environment-specific configurations

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (celery namespace)    │
│                                                             │
│  ┌──────────────┐         ┌──────────────┐                │
│  │   FastAPI    │         │    Flower    │                │
│  │     API      │         │  Monitoring  │                │
│  │  (Port 8000) │         │  (Port 5555) │                │
│  └──────┬───────┘         └──────┬───────┘                │
│         │                         │                         │
│         │        ┌────────────────┘                        │
│         │        │                                         │
│         ▼        ▼                                         │
│  ┌──────────────────────────────┐                         │
│  │          Redis               │                          │
│  │   (Broker + Backend)         │                          │
│  │   StatefulSet - 2Gi PVC      │                          │
│  └──────────┬───────────────────┘                         │
│             │                                               │
│             │  Task Queue                                   │
│             │                                               │
│         ┌───▼────────────────────┐                         │
│         │   Celery Workers       │                         │
│         │   (Deployment - 2x)    │                         │
│         └───┬────────────────────┘                         │
│             │                                               │
│             │  File I/O (boto3)                            │
│             │                                               │
│         ┌───▼────────────────────┐                         │
│         │    SeaweedFS S3        │                         │
│         │  (Object Storage)      │                         │
│         │  Master + Volume + Filer│                        │
│         └────────────────────────┘                         │
│                                                             │
│  ┌─────────────────────────────────────────────┐          │
│  │              Velero                          │          │
│  │  (Backup CSI Snapshots → SeaweedFS S3)      │          │
│  └─────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### Workflow Execution Flow

```
1. Client sends POST /workflows with parameters
        ↓
2. FastAPI creates Celery task chain
        ↓
3. Tasks queued to Redis
        ↓
4. Worker picks up first task (add)
        ↓
5. Result passed to next task (multiply)
        ↓
6. Final result saved to SeaweedFS S3
        ↓
7. Task ID returned to client
        ↓
8. Client polls GET /workflows/{id}/status
```

### Task Chain Example

The included `workflow_example` demonstrates task chaining:

```python
workflow = chain(
    add.s(a, b),              # Step 1: Add two numbers (2 sec delay)
    multiply.s(10),           # Step 2: Multiply result by 10
    save_to_seaweed.s(filename)  # Step 3: Save to S3 bucket
)
```

## Prerequisites

### Required Tools

- **Kubernetes cluster** - Docker Desktop (local), minikube, or production cluster
- **kubectl** - Kubernetes CLI (v1.30+)
- **helm** - Helm 3.x package manager
- **make** - GNU Make for automation
- **Docker** - For building container images
- **velero** - CLI for backup operations (optional but recommended)

### For Local Development

- **Python 3.13+** - For local testing
- **uv** - Fast Python package manager (optional, used in Dockerfile)
- **Docker Desktop** - For Kubernetes local testing

### Cluster Requirements

#### Local Testing (Docker Desktop)

- CSI Hostpath Driver
- CSI Snapshot CRDs and Controller
- Minimum 4GB RAM allocated to Docker Desktop

#### Production

- Longhorn distributed storage system
- CSI Snapshot CRDs and Controller
- Adequate node resources for worker scaling

## Installation

### Step 1: Build Docker Image

```bash
# Build the application image
make docker/build

# For local testing, ensure image is available to cluster
# Docker Desktop: Already available
# minikube: minikube image load celery-workflows:latest
```

### Step 2: Prepare Helm Chart

```bash
# Update Helm dependencies (SeaweedFS, Longhorn)
make helm/dep-update

# Package the chart
make helm/package
```

This creates `helm/charts/celery-workflows-0.1.0.tgz`.

### Step 3: Install CSI Snapshot Support (Local Only)

Required for backup functionality on Docker Desktop:

```bash
# Install CSI Snapshot CRDs and Controller
make csi/install-all

# Install CSI Hostpath Driver
curl -sLO https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/master/deploy/kubernetes-1.30/deploy.sh
chmod +x deploy.sh
./deploy.sh

# Create StorageClass
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-hostpath-sc
provisioner: hostpath.csi.k8s.io
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
```

### Step 4: Deploy to Kubernetes

```bash
# Deploy for local development (default)
make helm/upgrade-local

# Or for production
make helm/upgrade-prod
```

The deployment uses environment-specific configuration files:
- `helm/values.yaml` - Base configuration (shared)
- `helm/values/local.yaml` - Local development overrides
- `helm/values/prod.yaml` - Production overrides

This creates the `celery` namespace and deploys:
- Redis StatefulSet with persistent storage
- SeaweedFS (Master, Volume, Filer, S3)
- FastAPI service
- Celery workers (2 replicas)
- Flower monitoring dashboard

### Step 5: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n celery

# Expected output:
# celery-workflows-api-xxx         1/1   Running
# celery-workflows-worker-xxx      1/1   Running (x2)
# celery-workflows-flower-xxx      1/1   Running
# celery-workflows-redis-0         1/1   Running
# seaweedfs-master-0               1/1   Running
# seaweedfs-volume-0               1/1   Running
# seaweedfs-filer-0                1/1   Running
# seaweedfs-s3-xxx                 1/1   Running
```

### Step 6: Access Services

After deployment, services are accessible via NodePort:

- **FastAPI Swagger UI**: http://localhost:30080/docs
- **Flower Dashboard**: http://localhost:30555
- **SeaweedFS Filer**: http://localhost:30899

## Configuration

### Environment Variables

The application uses Pydantic Settings for configuration. All settings are injected via environment variables in the Kubernetes deployments.

**Required Settings:**

| Variable | Purpose | Default |
|----------|---------|---------|
| `CELERY_BROKER_URL` | Redis broker connection | `redis://celery-workflows-redis:6379/0` |
| `CELERY_RESULT_BACKEND` | Redis result storage | `redis://celery-workflows-redis:6379/0` |
| `SEAWEEDFS_S3_URL` | S3 endpoint for storage | `http://seaweedfs-s3:8333` |

### Helm Values

Configuration is managed in `helm/values.yaml`:

#### Application Settings

```yaml
namespace: celery
image:
  repository: celery-workflows
  tag: latest
  pullPolicy: IfNotPresent
replicaCount: 2  # Number of worker replicas
```

#### Redis Configuration

```yaml
redis:
  image: redis:7
  port: 6379
  storage: 2Gi  # PVC size
```

#### SeaweedFS Configuration

```yaml
seaweedfs:
  enabled: true
  master:
    replicas: 1
    data:
      size: "5Gi"
      storageClass: "csi-hostpath-sc"  # or "longhorn" for production
  volume:
    replicas: 1
    dataDirs:
      - size: "5Gi"
        storageClass: "csi-hostpath-sc"
  filer:
    enabled: true
    port: 8899
    nodePort: 30899
  s3:
    enabled: true
    enabledAuth: true
    existingConfigSecret: seaweedfs
```

#### Resource Limits

```yaml
# Per component (example for API)
api:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

Full resource limits documented in `helm/templates/*/deployment.yaml`.

#### Velero Backup

```yaml
velero:
  enabled: false  # Enable after velero/install
  s3:
    bucket: velero-backups
    accessKey: accessKey
    secretKey: secretKey
  schedule:
    enabled: false  # Enable for daily backups
    cron: "0 2 * * *"
    ttl: 720h  # 30 days
```

### Environment-Specific Configuration

The chart uses a layered configuration approach with separate files for different environments:

**Configuration Files:**
- `helm/values.yaml` - Base configuration shared across all environments
- `helm/values/local.yaml` - Local development overrides
- `helm/values/prod.yaml` - Production overrides

**Key Differences:**

| Setting | Local | Production |
|---------|-------|------------|
| Storage Class | `csi-hostpath-sc` | `longhorn` |
| Worker Replicas | 2 | 3 |
| Redis Storage | 2Gi | 10Gi |
| Image Pull Policy | IfNotPresent | Always |
| Longhorn | Disabled | Enabled (3 replicas) |
| Velero Backups | Disabled | Enabled with schedule |

**Deployment:**

```bash
# Local development
make helm/upgrade-local

# Production
make helm/upgrade-prod

# Or with ENV variable
make helm/upgrade ENV=local
make helm/upgrade ENV=prod
```

For detailed environment configuration, see [docs/ENVIRONMENTS.md](docs/ENVIRONMENTS.md).

## Usage

### API Endpoints

The FastAPI application exposes the following endpoints:

#### Create Workflow

```bash
POST /workflows
Content-Type: application/json

{
  "a": 5,
  "b": 3
}
```

**Response:**
```json
{
  "task_id": "8d8e4821-5c21-4e71-9f8d-0a4e8b3d2c1f"
}
```

**Example:**
```bash
curl -X POST http://localhost:30080/workflows \
  -H "Content-Type: application/json" \
  -d '{"a": 5, "b": 3}'
```

This triggers the workflow chain:
1. Add 5 + 3 = 8
2. Multiply 8 * 10 = 80
3. Save result to SeaweedFS S3

#### Check Task Status

```bash
GET /workflows/{task_id}/status
```

**Response (Pending):**
```json
{
  "task_id": "8d8e4821-5c21-4e71-9f8d-0a4e8b3d2c1f",
  "status": "PENDING",
  "result": null
}
```

**Response (Success):**
```json
{
  "task_id": "8d8e4821-5c21-4e71-9f8d-0a4e8b3d2c1f",
  "status": "SUCCESS",
  "result": 80
}
```

**Example:**
```bash
curl http://localhost:30080/workflows/8d8e4821-5c21-4e71-9f8d-0a4e8b3d2c1f/status
```

#### API Documentation

Interactive API documentation is available at:
- **Swagger UI**: http://localhost:30080/docs
- **ReDoc**: http://localhost:30080/redoc

### Included Tasks

The project includes example tasks in `src/tasks/workflows.py`:

#### 1. add(x, y)

Simple addition with a 2-second delay to simulate work.

```python
@celery_app.task(bind=True, autoretry_for=(Exception,), retry_kwargs={'max_retries': 3})
def add(self, x: int, y: int) -> int:
    time.sleep(2)
    result = x + y
    return result
```

#### 2. multiply(x, y)

Multiplies two numbers.

```python
@celery_app.task
def multiply(x: int, y: int) -> int:
    result = x * y
    return result
```

#### 3. save_to_seaweed(result, filename)

Saves task result to SeaweedFS S3 storage.

```python
@celery_app.task
def save_to_seaweed(result: int, filename: str) -> dict:
    # Creates 'results' bucket if not exists
    # Uploads JSON file with result
    # Returns S3 location
```

#### 4. workflow_example(a, b)

Chains all tasks together into a complete workflow.

```python
@celery_app.task
def workflow_example(a: int, b: int):
    filename = f"result_{uuid.uuid4()}.json"
    workflow = chain(
        add.s(a, b),
        multiply.s(10),
        save_to_seaweed.s(filename)
    )
    return workflow.apply_async().id
```

### Complete Workflow Example

```bash
# 1. Trigger workflow
TASK_ID=$(curl -s -X POST http://localhost:30080/workflows \
  -H "Content-Type: application/json" \
  -d '{"a": 7, "b": 3}' | jq -r '.task_id')

echo "Task ID: $TASK_ID"

# 2. Check status (repeat until SUCCESS)
curl http://localhost:30080/workflows/$TASK_ID/status | jq

# 3. View result in Flower dashboard
open http://localhost:30555

# 4. Result file is stored in SeaweedFS S3
# Bucket: results
# File: result_<uuid>.json
# Content: {"result": 100}  # (7+3)*10
```

## Workflow Development

### Creating New Tasks

1. Create a new file in `src/tasks/` (e.g., `src/tasks/my_tasks.py`)
2. Import the Celery app
3. Define your task using the `@celery_app.task` decorator

**Example:**

```python
# src/tasks/my_tasks.py
from src.core.celery import celery_app
import requests

@celery_app.task(bind=True, autoretry_for=(Exception,), retry_kwargs={'max_retries': 3})
def fetch_data(self, url: str) -> dict:
    """Fetch data from an external API."""
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return response.json()

@celery_app.task
def process_data(data: dict) -> dict:
    """Process the fetched data."""
    # Your processing logic here
    return {"processed": True, "count": len(data)}
```

Tasks are automatically discovered by Celery on worker startup (configured in `src/core/celery.py`).

### Creating Workflow Chains

Combine tasks into workflows using Celery's `chain`:

```python
from celery import chain
from src.tasks.my_tasks import fetch_data, process_data
from src.tasks.workflows import save_to_seaweed

@celery_app.task
def data_pipeline(api_url: str):
    filename = f"pipeline_{uuid.uuid4()}.json"
    workflow = chain(
        fetch_data.s(api_url),
        process_data.s(),
        save_to_seaweed.s(filename)
    )
    return workflow.apply_async().id
```

### Adding API Endpoints

1. Create a new router in `src/api/routers/`
2. Define your endpoints
3. Register the router in `src/api/main.py`

**Example:**

```python
# src/api/routers/my_routes.py
from fastapi import APIRouter, Depends
from src.core.celery import celery_app
from src.api.deps import get_celery_app

router = APIRouter(prefix="/my-workflow", tags=["my-workflow"])

@router.post("/")
def trigger_my_workflow(url: str, celery: Celery = Depends(get_celery_app)):
    from src.tasks.my_tasks import data_pipeline
    task_id = data_pipeline.delay(url)
    return {"task_id": str(task_id)}
```

```python
# src/api/main.py
from src.api.routers import my_routes

app.include_router(my_routes.router)
```

### Task Best Practices

1. **Use bind=True** for access to task context (self.request.id, etc.)
2. **Configure retries** with `autoretry_for` and `retry_kwargs`
3. **Set timeouts** for external API calls
4. **Log progress** using `self.update_state()` for long-running tasks
5. **Handle errors gracefully** and return meaningful error messages
6. **Keep tasks idempotent** when possible
7. **Use task signatures** (`.s()`) for chaining

## Monitoring

### Flower Dashboard

Flower provides real-time monitoring of Celery workers and tasks.

**Access:** http://localhost:30555

**Features:**
- **Tasks**: View active, scheduled, and completed tasks
- **Workers**: Monitor worker status, uptime, and resource usage
- **Broker**: Redis connection status and queue lengths
- **Task History**: Search and filter task execution history
- **Task Details**: View arguments, results, exceptions, and execution time
- **Worker Pool**: Inspect worker processes and threads

**Key Metrics:**
- Total tasks processed
- Task success/failure rates
- Average task runtime
- Active worker count
- Queue backlog

### Kubernetes Monitoring

```bash
# View all resources
make k8s/get-all

# Check pod status
kubectl get pods -n celery

# View logs
kubectl logs -n celery deployment/celery-workflows-worker -f
kubectl logs -n celery deployment/celery-workflows-api -f

# Check resource usage
kubectl top pods -n celery
kubectl top nodes

# Describe pod for events
kubectl describe pod <pod-name> -n celery
```

### Redis Monitoring

```bash
# Connect to Redis CLI
kubectl exec -n celery celery-workflows-redis-0 -- redis-cli

# Inside Redis:
INFO           # Server statistics
DBSIZE         # Number of keys
KEYS *         # List all keys (use with caution in production)
GET <key>      # Get value
```

## Backup and Restore

This deployment includes comprehensive disaster recovery using Velero with CSI volume snapshots.

### Initial Setup

```bash
# 1. Install CSI snapshot support (if not already done)
make csi/install-all

# 2. Install Velero server (one-time operation)
make velero/install

# 3. Enable Velero in the Helm chart
make velero/enable
```

### Manual Backups

```bash
# Create a manual backup
make velero/backup

# List all backups
make velero/backup-list

# Describe backup details
velero backup describe <backup-name> -n celery --details
```

### Scheduled Backups

```bash
# Enable daily backups at 02:00 UTC
make velero/schedule-enable

# Disable scheduled backups
make velero/schedule-disable

# View schedule status
kubectl get schedule -n celery
```

### Restore Operations

```bash
# List available backups
make velero/backup-list

# Restore from a specific backup
make velero/restore BACKUP_NAME=<backup-name>

# Monitor restore progress
velero restore describe <restore-name> -n celery
```

### What Gets Backed Up

- All Kubernetes resources in the `celery` namespace
- Persistent Volume Claims (Redis data, SeaweedFS storage)
- CSI Volume Snapshots of all PVCs

### Backup Storage

Backups are stored in SeaweedFS S3:
- **Bucket**: `velero-backups`
- **Location**: SeaweedFS S3 (cluster-internal)
- **Retention**: 30 days (configurable via `velero.schedule.ttl`)

For detailed backup documentation, see [docs/BACKUP.md](docs/BACKUP.md).

## Project Structure

```
celery-workflows/
├── src/                          # Application source code
│   ├── api/                      # FastAPI REST API
│   │   ├── main.py              # Application entry point
│   │   ├── routers/
│   │   │   └── workflows.py     # Workflow API endpoints
│   │   └── deps.py              # Dependency injection
│   ├── core/                    # Core configuration
│   │   ├── celery.py            # Celery app initialization
│   │   └── config.py            # Settings with Pydantic
│   ├── tasks/                   # Celery task definitions
│   │   └── workflows.py         # Example tasks and workflows
│   └── schemas/                 # Pydantic models
│       └── workflows.py         # Request/response schemas
├── helm/                        # Kubernetes Helm chart
│   ├── Chart.yaml              # Chart metadata
│   ├── Chart.lock              # Dependency lock
│   ├── values.yaml             # Base configuration (shared)
│   ├── values/                 # Environment-specific overrides
│   │   ├── local.yaml          # Local development
│   │   └── prod.yaml           # Production
│   ├── templates/              # Kubernetes manifests
│   │   ├── api/                # FastAPI deployment & service
│   │   ├── celery/             # Worker deployment
│   │   ├── flower/             # Flower deployment & service
│   │   ├── redis/              # Redis StatefulSet & service
│   │   ├── seaweedfs/          # SeaweedFS secrets
│   │   ├── velero/             # Backup components
│   │   └── NOTES.txt           # Post-install instructions
│   └── charts/                 # Packaged dependencies
├── docs/                        # Documentation
│   ├── BACKUP.md               # Backup/restore guide
│   └── ENVIRONMENTS.md         # Environment configuration guide
├── Dockerfile                  # Python 3.13 application image
├── docker-compose.yml          # Local development compose
├── pyproject.toml              # Python dependencies
├── Makefile                    # Automation scripts
└── README.md                   # This file
```

### Key Files

**Application:**
- `src/api/main.py` - FastAPI application initialization and router registration
- `src/core/celery.py` - Celery app configuration with auto-discovery
- `src/core/config.py` - Environment-based configuration management
- `src/tasks/workflows.py` - Example task definitions and workflow chains

**Deployment:**
- `helm/values.yaml` - Base configuration shared across environments
- `helm/values/local.yaml` - Local development overrides
- `helm/values/prod.yaml` - Production environment overrides
- `helm/templates/*` - Kubernetes resource definitions
- `Dockerfile` - Container image definition using Python 3.13 and uv

**Configuration:**
- `pyproject.toml` - Python project metadata and dependencies

## Troubleshooting

### Pods Not Starting

**Check pod status:**
```bash
kubectl get pods -n celery
```

**Common states:**
- `ImagePullBackOff` - Image not available. Rebuild or load image to cluster.
- `CrashLoopBackOff` - Pod crashes on startup. Check logs.
- `Pending` - Waiting for resources or PVC binding. Check events.

**View pod events:**
```bash
kubectl describe pod <pod-name> -n celery
```

**Check logs:**
```bash
kubectl logs <pod-name> -n celery
kubectl logs <pod-name> -n celery --previous  # Previous container instance
```

### Worker Not Picking Up Tasks

**Check worker logs:**
```bash
kubectl logs -n celery deployment/celery-workflows-worker -f
```

**Verify Redis connection:**
```bash
# Connect to Redis
kubectl exec -n celery celery-workflows-redis-0 -- redis-cli PING
# Should return: PONG

# Check queue
kubectl exec -n celery celery-workflows-redis-0 -- redis-cli LLEN celery
```

**Check worker registration in Flower:**
Open http://localhost:30555 and navigate to "Workers" tab.

### Tasks Failing

**View task details in Flower:**
1. Open http://localhost:30555
2. Navigate to "Tasks"
3. Click on failed task ID
4. View exception traceback

**Check task logs:**
```bash
kubectl logs -n celery deployment/celery-workflows-worker -f | grep "Task.*\[FAILURE\]"
```

### Storage Issues

**Check PVC status:**
```bash
kubectl get pvc -n celery

# All should be "Bound"
# If "Pending", check StorageClass exists
```

**Verify StorageClass:**
```bash
kubectl get storageclass

# For local: csi-hostpath-sc should exist
# For production: longhorn should exist
```

**Check CSI Hostpath Driver (local):**
```bash
kubectl get pods -n kube-system | grep csi-hostpath

# Should show:
# csi-hostpath-plugin-xxx     3/3   Running
# csi-snapshotter-xxx         1/1   Running
```

### SeaweedFS S3 Issues

**Check S3 pod:**
```bash
kubectl get pods -n celery | grep seaweedfs-s3
kubectl logs -n celery <seaweedfs-s3-pod>
```

**Test S3 connectivity:**
```bash
kubectl run -n celery aws-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=accessKey" \
  --env="AWS_SECRET_ACCESS_KEY=secretKey" \
  --env="AWS_DEFAULT_REGION=us-east-1" \
  --command -- aws s3 ls --endpoint-url http://seaweedfs-s3:8333
```

**Check credentials:**
```bash
kubectl get secret -n celery seaweedfs -o jsonpath='{.data.seaweedfs_s3_config}' | base64 -d
```

### Redis Connection Issues

**Check Redis service:**
```bash
kubectl get svc -n celery celery-workflows-redis
```

**Test Redis connectivity from worker:**
```bash
kubectl exec -n celery deployment/celery-workflows-worker -- \
  python -c "import redis; r = redis.Redis(host='celery-workflows-redis', port=6379); print(r.ping())"
```

### API Not Accessible

**Check API service:**
```bash
kubectl get svc -n celery celery-workflows-api
# Should show NodePort 30080
```

**Check API logs:**
```bash
kubectl logs -n celery deployment/celery-workflows-api -f
```

**Test from within cluster:**
```bash
kubectl run -n celery curl-test --rm -i --restart=Never --image=curlimages/curl -- \
  curl http://celery-workflows-api:8000/docs
```

### Backup Issues

See detailed troubleshooting in [docs/BACKUP.md](docs/BACKUP.md#troubleshooting).

**Quick checks:**

```bash
# Check Velero pod
kubectl get pods -n celery | grep velero

# Check BackupStorageLocation
kubectl get backupstoragelocation -n celery
# Phase should be "Available"

# Check recent backups
velero backup get -n celery
```

## Makefile Reference

### Docker

| Target | Description |
|--------|-------------|
| `make docker/build` | Build application Docker image |

### Helm

| Target | Description |
|--------|-------------|
| `make helm/dep-update` | Update Helm chart dependencies |
| `make helm/package` | Package Helm chart to `.tgz` |
| `make helm/upgrade` | Deploy or upgrade (uses ENV=local or prod) |
| `make helm/upgrade-local` | Deploy to local environment |
| `make helm/upgrade-prod` | Deploy to production environment |
| `make helm/uninstall` | Remove release from cluster |

### CSI Snapshots

| Target | Description |
|--------|-------------|
| `make csi/install-crds` | Install CSI Snapshot CRDs |
| `make csi/install-controller` | Install CSI Snapshot Controller |
| `make csi/install-all` | Install both CRDs and Controller |

### Velero Backup

| Target | Description |
|--------|-------------|
| `make velero/install` | Install Velero server (one-time) |
| `make velero/uninstall` | Remove Velero server |
| `make velero/enable` | Enable Velero in Helm chart |
| `make velero/backup` | Create manual backup |
| `make velero/backup-list` | List all backups |
| `make velero/restore BACKUP_NAME=<name>` | Restore from backup |
| `make velero/schedule-enable` | Enable scheduled daily backups |
| `make velero/schedule-disable` | Disable scheduled backups |

### Kubernetes

| Target | Description |
|--------|-------------|
| `make k8s/get-all` | List all resources in celery namespace |

### Help

| Target | Description |
|--------|-------------|
| `make help` | Display all available targets |

## Technology Stack

- **Python 3.13** - Application runtime
- **FastAPI 0.128+** - Modern web framework with async support
- **Celery 5.3+** - Distributed task queue
- **Redis 7** - Message broker and result backend
- **Flower 2.0+** - Celery monitoring web UI
- **boto3** - AWS SDK for S3 operations
- **Pydantic 2.x** - Data validation and settings
- **Kubernetes 1.30+** - Container orchestration
- **Helm 3.x** - Kubernetes package manager
- **SeaweedFS 4.0** - S3-compatible object storage
- **Longhorn 1.7** - Distributed block storage
- **Velero 1.17** - Backup and disaster recovery

## Dependencies

Full Python dependencies are managed in `pyproject.toml`:

```toml
[project]
dependencies = [
    "celery[redis]>=5.3.1",
    "redis>=7.1.0",
    "fastapi>=0.128.0",
    "uvicorn[standard]>=0.40.0",
    "flower>=2.0.1",
    "boto3>=1.42.39",
    "pydantic-settings>=2.12.0",
]
```

Helm dependencies are defined in `helm/Chart.yaml`:

```yaml
dependencies:
  - name: seaweedfs
    version: 4.0.407
    repository: https://seaweedfs.github.io/seaweedfs/helm
  - name: longhorn
    version: 1.7.2
    repository: https://charts.longhorn.io
    condition: longhorn.enabled
```

## Contributing

Contributions are welcome. Please ensure:

1. All new tasks include proper error handling and retry logic
2. API endpoints include request/response schemas
3. New features include appropriate tests
4. Documentation is updated for any configuration changes
5. Resource limits are defined for new deployments

## License

[Add your license here]

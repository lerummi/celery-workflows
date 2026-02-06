# Environment-Specific Deployments

This guide explains how to deploy the Celery Workflows application to different environments (local development vs production).

## Overview

The Helm chart uses a layered configuration approach:

```
helm/values.yaml          <- Base configuration (shared)
helm/values/local.yaml    <- Local development overrides
helm/values/prod.yaml     <- Production overrides
```

Helm merges these files in order, with later files overriding earlier ones.

## Configuration Layers

### Base Configuration (values.yaml)

Contains shared settings across all environments:
- Namespace and image repository
- Service ports (API, Flower, Redis, SeaweedFS)
- Base application structure
- Longhorn and Velero base configuration

### Local Development (values/local.yaml)

Optimized for Docker Desktop/Minikube:
- **Storage**: CSI Hostpath Driver (`csi-hostpath-sc`)
- **Image Pull Policy**: `IfNotPresent` (uses locally built images)
- **Worker Replicas**: 2
- **Resource Limits**: Conservative (suitable for laptops)
- **Storage Sizes**: Smaller (2Gi Redis, 5Gi SeaweedFS)
- **Longhorn**: Disabled
- **Velero**: Disabled by default

### Production (values/prod.yaml)

Optimized for production clusters:
- **Storage**: Longhorn (`longhorn` StorageClass)
- **Image Pull Policy**: `Always` (pulls latest images)
- **Worker Replicas**: 3
- **Resource Limits**: Higher (optimized for production workloads)
- **Storage Sizes**: Larger (10Gi Redis, 20-50Gi SeaweedFS)
- **Longhorn**: Enabled with 3 replicas
- **Velero**: Enabled with scheduled backups

## Key Differences

| Setting | Local | Production |
|---------|-------|------------|
| **Storage Class** | `csi-hostpath-sc` | `longhorn` |
| **Worker Replicas** | 2 | 3 |
| **Redis Storage** | 2Gi | 10Gi |
| **SeaweedFS Master** | 1 replica, 5Gi | 2 replicas, 20Gi |
| **SeaweedFS Volume** | 1 replica, 5Gi | 3 replicas, 50Gi |
| **Image Pull Policy** | IfNotPresent | Always |
| **Longhorn** | Disabled | Enabled (3 replicas) |
| **Velero Backups** | Disabled | Enabled with schedule |
| **API CPU** | 100m-500m | 250m-1000m |
| **API Memory** | 128Mi-256Mi | 256Mi-512Mi |
| **Worker CPU** | 100m-500m | 250m-2000m |
| **Worker Memory** | 256Mi-512Mi | 512Mi-2Gi |

## Deployment Commands

### Local Development

```bash
# Standard deployment
make helm/upgrade ENV=local

# Or use the convenience target
make helm/upgrade-local

# With Velero enabled
make velero/enable ENV=local
```

### Production

```bash
# Standard deployment
make helm/upgrade ENV=prod

# Or use the convenience target
make helm/upgrade-prod

# With Velero enabled (automatically includes scheduled backups)
make velero/enable ENV=prod
```

### Manual Helm Commands

If you prefer to use Helm directly:

```bash
# Local
helm upgrade --install celery-workflows \
  helm/charts/celery-workflows-0.1.0.tgz \
  -f helm/values.yaml \
  -f helm/values/local.yaml \
  -n celery --create-namespace

# Production
helm upgrade --install celery-workflows \
  helm/charts/celery-workflows-0.1.0.tgz \
  -f helm/values.yaml \
  -f helm/values/prod.yaml \
  -n celery --create-namespace
```

## Switching from Local to Production

### Prerequisites

1. **Production Kubernetes Cluster** with adequate resources
2. **CSI Snapshot Support** installed:
   ```bash
   make csi/install-all
   ```
3. **Longhorn** will be installed automatically (configured in Helm dependencies)

### Migration Steps

#### Step 1: Backup Current State

```bash
# If you have data in local that you want to keep
# Create a backup first (requires Velero)
make velero/install
make velero/enable ENV=local
make velero/backup
```

#### Step 2: Package Chart

```bash
make helm/dep-update
make helm/package
```

#### Step 3: Deploy to Production

```bash
# Deploy with production settings
make helm/upgrade-prod

# Or with environment variable
make helm/upgrade ENV=prod
```

#### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n celery

# Expected pods:
# - celery-workflows-worker (3 replicas)
# - celery-workflows-api (1 replica)
# - celery-workflows-flower (1 replica)
# - celery-workflows-redis-0 (1 StatefulSet)
# - seaweedfs-master-0, seaweedfs-master-1 (2 replicas)
# - seaweedfs-volume-0, seaweedfs-volume-1, seaweedfs-volume-2 (3 replicas)
# - seaweedfs-filer-0 (1 replica)
# - seaweedfs-s3-xxx (1 deployment)

# Check storage
kubectl get pvc -n celery
# All PVCs should use 'longhorn' StorageClass

# Check Longhorn
kubectl get pods -n longhorn-system
```

#### Step 5: Enable Backups (Production)

```bash
# Install Velero
make velero/install

# Enable Velero with scheduled backups
make velero/enable ENV=prod

# Scheduled backups are automatically enabled in production
# (configured in values/prod.yaml)
```

#### Step 6: Restore Data (if needed)

```bash
# List backups from local environment
make velero/backup-list

# Restore specific backup
make velero/restore BACKUP_NAME=<backup-name>
```

## Customizing Environments

### Creating a Custom Environment

You can create additional environment files for staging, QA, etc:

```bash
# Create values/staging.yaml
cp helm/values/prod.yaml helm/values/staging.yaml

# Edit as needed
vim helm/values/staging.yaml

# Deploy
make helm/upgrade ENV=staging
```

### Override Specific Values

You can override individual values without creating a new file:

```bash
# Override worker replicas for production
helm upgrade --install celery-workflows \
  helm/charts/celery-workflows-0.1.0.tgz \
  -f helm/values.yaml \
  -f helm/values/prod.yaml \
  --set replicaCount=5 \
  -n celery
```

### Common Customizations

**Increase worker replicas:**
```yaml
# values/prod.yaml
replicaCount: 5
```

**Use external S3 for Velero backups:**
```yaml
# values/prod.yaml
velero:
  s3:
    bucket: my-prod-backups
    accessKey: AWS_ACCESS_KEY
    secretKey: AWS_SECRET_KEY
    region: eu-central-1
  bsl:
    name: aws-s3-bsl
```

**Change service types to LoadBalancer:**
```yaml
# values/prod.yaml
api:
  serviceType: LoadBalancer
  # nodePort not needed for LoadBalancer

flower:
  serviceType: LoadBalancer
```

## Troubleshooting

### Wrong StorageClass Used

**Problem:** PVCs are using the wrong StorageClass after deployment.

**Solution:**
```bash
# Check which environment was used
kubectl get pvc -n celery -o yaml | grep storageClassName

# Redeploy with correct environment
make helm/upgrade ENV=prod
```

### Image Not Pulling in Production

**Problem:** Pods stuck in `ImagePullBackOff`.

**Cause:** Production uses `pullPolicy: Always` but image is only available locally.

**Solution:**
```bash
# Push image to registry
docker tag celery-workflows:latest your-registry/celery-workflows:latest
docker push your-registry/celery-workflows:latest

# Update values/prod.yaml
image:
  repository: your-registry/celery-workflows
  tag: latest
  pullPolicy: Always
```

### Longhorn Not Available

**Problem:** PVCs stuck in `Pending` state with "no volume plugin matched".

**Cause:** Longhorn not installed or not ready.

**Solution:**
```bash
# Check Longhorn installation
kubectl get pods -n longhorn-system

# If not installed, it should install automatically via Helm dependency
# Verify Chart.yaml has longhorn dependency:
helm dependency list ./helm

# Manually trigger dependency update
make helm/dep-update
make helm/package
make helm/upgrade ENV=prod
```

### Velero Schedule Not Working

**Problem:** Scheduled backups not running in production.

**Cause:** `velero.schedule.enabled` might be overridden.

**Solution:**
```bash
# Check schedule exists
kubectl get schedule -n celery

# If missing, re-enable
make velero/schedule-enable ENV=prod

# Verify in values/prod.yaml:
velero:
  enabled: true
  schedule:
    enabled: true
```

## Best Practices

1. **Always test locally first** before deploying to production
2. **Use version tags** in production instead of `latest`:
   ```yaml
   # values/prod.yaml
   image:
     tag: v1.2.3
   ```
3. **Keep secrets out of values files** - use Kubernetes secrets or external secret managers
4. **Monitor resource usage** and adjust limits in environment files accordingly
5. **Enable backups in production** - configure Velero schedule in `values/prod.yaml`
6. **Document custom changes** - if you modify environment files, add comments explaining why

## See Also

- [Main README](../README.md) - General deployment guide
- [Backup Documentation](BACKUP.md) - Velero backup/restore procedures
- [Helm Values Reference](../helm/values.yaml) - Base configuration options

# Velero Backup & Restore Documentation

## Overview

This Celery Workflows deployment uses [Velero](https://velero.io/) for backup and restore operations. The backup system captures both Kubernetes manifests and Persistent Volume Claims (PVCs) using CSI volume snapshots.

**Key Features:**
- Automated or manual backups of the entire `celery` namespace
- CSI volume snapshots for PVC data (Redis, SeaweedFS)
- S3-compatible storage via SeaweedFS
- Configurable retention policies (default: 30 days)
- Optional scheduled backups (daily at 02:00 UTC)

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (celery namespace)                  │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐ │
│  │  Redis   │  │ SeaweedFS│  │  API/Worker/Flower   │ │
│  │   PVC    │  │   PVCs   │  │    (Stateless)       │ │
│  └────┬─────┘  └────┬─────┘  └──────────────────────┘ │
│       │             │                                  │
│       └─────────────┴──────────┐                      │
│                                 │                       │
│                          ┌──────▼──────┐               │
│                          │   Velero    │               │
│                          │   Server    │               │
│                          └──────┬──────┘               │
│                                 │                       │
│       ┌─────────────────────────┴─────────────┐        │
│       │                                       │        │
│  ┌────▼────────┐                    ┌────────▼──────┐ │
│  │ CSI Driver  │                    │  SeaweedFS S3 │ │
│  │  Snapshots  │                    │ (BSL Storage) │ │
│  └─────────────┘                    └───────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Storage

- **Local Testing:** CSI Hostpath Driver (`csi-hostpath-sc` StorageClass)
- **Production:** Longhorn (`longhorn` StorageClass)
- **Backup Storage:** SeaweedFS S3 (bucket: `velero-backups`)

### What Gets Backed Up

**Included:**
- All Kubernetes resources in the `celery` namespace (Deployments, StatefulSets, Services, ConfigMaps, Secrets)
- Persistent Volume Claims (Redis data, SeaweedFS data)
- Volume Snapshots (CSI snapshots of PVC data)

**Excluded:**
- Velero's own resources (BackupStorageLocation, Schedule CRs)
- VolumeSnapshot/VolumeSnapshotContent resources (snapshots are captured via CSI)

## Prerequisites

### Required Tools

1. **Velero CLI** - Install from [velero.io](https://velero.io/docs/main/basic-install/)
   ```bash
   # macOS
   brew install velero

   # Linux
   wget https://github.com/vmware-tanzu/velero/releases/latest/download/velero-linux-amd64.tar.gz
   tar -xvf velero-linux-amd64.tar.gz
   sudo mv velero-linux-amd64/velero /usr/local/bin/
   ```

2. **kubectl** - Kubernetes CLI
3. **helm** - Helm package manager
4. **make** - For using Makefile targets

### Cluster Prerequisites

#### For Local Testing (Docker Desktop)

1. **CSI Snapshot CRDs and Controller:**
   ```bash
   make csi/install-all
   ```

2. **CSI Hostpath Driver:**
   ```bash
   curl -sLO https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/master/deploy/kubernetes-1.30/deploy.sh
   chmod +x deploy.sh
   ./deploy.sh
   ```

3. **StorageClass:**
   ```bash
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

#### For Production

1. **CSI Snapshot CRDs and Controller:**
   ```bash
   make csi/install-all
   ```

2. **Longhorn Storage** (if not already installed):
   - Enable in `helm/values.yaml`:
     ```yaml
     longhorn:
       enabled: true
     ```
   - Longhorn will be installed as a Helm dependency

## Initial Setup

### 1. Package the Helm Chart

```bash
make helm/dep-update
make helm/package
```

### 2. Install Velero Server

This is a **one-time operation** that installs the Velero server components:

```bash
make velero/install
```

This command:
- Installs Velero CRDs (Backup, Restore, BackupStorageLocation, etc.)
- Deploys the Velero server in the `celery` namespace
- Configures the AWS S3 plugin for SeaweedFS compatibility
- Enables CSI snapshot support

**Important:** The Velero server must be installed **before** enabling Velero in the Helm chart.

### 3. Enable Velero in the Chart

This activates the BackupStorageLocation and creates the S3 bucket:

```bash
make velero/enable
```

This command:
- Upgrades the Helm release with `velero.enabled=true`
- Creates the BackupStorageLocation CR pointing to SeaweedFS S3
- Runs the bucket-init hook job (creates `velero-backups` bucket in SeaweedFS)
- Creates credentials secret for S3 access

### 4. Verify Installation

```bash
# Check Velero server status
kubectl get pods -n celery -l deploy=velero

# Check BackupStorageLocation
kubectl get backupstoragelocation -n celery

# Expected output:
# NAME            PHASE       LAST VALIDATED   AGE     DEFAULT
# seaweedfs-bsl   Available   5s               2m      true
```

## Manual Backups

### Create a Backup

```bash
make velero/backup
```

This creates a backup with the naming pattern `manual-<timestamp>` and includes:
- All resources in the `celery` namespace
- CSI volume snapshots of all PVCs

**Manual command (without Makefile):**
```bash
velero backup create manual-$(date +%s) \
  --include-namespaces celery \
  --storage-location seaweedfs-bsl \
  --snapshot-volumes=true \
  -n celery
```

### List All Backups

```bash
make velero/backup-list
```

**Manual command:**
```bash
velero backup get -n celery
```

**Example output:**
```
NAME                STATUS      CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
manual-1770359087   Completed   2026-02-06 07:24:48 +0100 CET   29d       seaweedfs-bsl      <none>
```

### Describe a Backup

```bash
velero backup describe <backup-name> -n celery
```

**With details (includes all backed up resources):**
```bash
velero backup describe <backup-name> -n celery --details
```

### View Backup Logs

```bash
velero backup logs <backup-name> -n celery
```

### Delete a Backup

```bash
velero backup delete <backup-name> -n celery
```

This deletes:
- The backup from Velero's tracking
- The backup data from SeaweedFS S3
- Associated volume snapshots

## Scheduled Backups

### Enable Scheduled Backups

To enable automatic daily backups at 02:00 UTC:

```bash
make velero/schedule-enable
```

This upgrades the chart with `velero.schedule.enabled=true`, creating a Velero Schedule CR.

**Manual command:**
```bash
helm upgrade --install celery-workflows \
  helm/charts/celery-workflows-0.1.0.tgz \
  -n celery --create-namespace \
  --set velero.enabled=true \
  --set velero.schedule.enabled=true
```

### Configure Schedule Settings

Edit `helm/values.yaml`:

```yaml
velero:
  enabled: true
  schedule:
    enabled: true
    name: celery-daily-backup
    cron: "0 2 * * *"     # Daily at 02:00 UTC
    ttl: 720h             # 30 days retention (720 hours)
```

**Cron Examples:**
- `0 2 * * *` - Daily at 02:00 UTC
- `0 */6 * * *` - Every 6 hours
- `0 2 * * 1` - Weekly on Mondays at 02:00 UTC
- `0 2 1 * *` - Monthly on the 1st at 02:00 UTC

After changing the schedule, repackage and upgrade:
```bash
make helm/package
make velero/schedule-enable
```

### Disable Scheduled Backups

```bash
make velero/schedule-disable
```

This keeps Velero enabled but removes the Schedule CR (manual backups still work).

### Check Schedule Status

```bash
kubectl get schedule -n celery
```

**Example output:**
```
NAME                  STATUS    SCHEDULE      LASTBACKUP   AGE
celery-daily-backup   Enabled   0 2 * * *     12m          5d
```

## Restore Operations

### List Available Backups

```bash
make velero/backup-list
```

### Restore from a Backup

To restore the entire `celery` namespace from a backup:

```bash
make velero/restore BACKUP_NAME=<backup-name>
```

**Manual command:**
```bash
velero restore create --from-backup <backup-name> -n celery
```

**Example:**
```bash
make velero/restore BACKUP_NAME=manual-1770359087
```

### Restore to a Different Namespace

```bash
velero restore create --from-backup <backup-name> \
  --namespace-mappings celery:celery-restore \
  -n celery
```

### Monitor Restore Progress

```bash
velero restore describe <restore-name> -n celery
```

**Get restore logs:**
```bash
velero restore logs <restore-name> -n celery
```

### List All Restores

```bash
velero restore get -n celery
```

### Restore Workflow Example

**Scenario:** Disaster recovery - the entire namespace was deleted

```bash
# 1. Verify backup exists
make velero/backup-list

# 2. Restore from the latest backup
make velero/restore BACKUP_NAME=manual-1770359087

# 3. Monitor the restore
velero restore describe restore-$(date +%Y%m%d) -n celery

# 4. Wait for restoration to complete (Phase: Completed)
kubectl get pods -n celery --watch

# 5. Verify PVCs were restored
kubectl get pvc -n celery

# 6. Verify volume snapshots were restored
kubectl get volumesnapshot -n celery
```

## Local vs Production

### Local Testing (Docker Desktop)

**Storage:**
- StorageClass: `csi-hostpath-sc`
- CSI Driver: `hostpath.csi.k8s.io`
- VolumeSnapshotClass: `csi-hostpath-snapclass`

**Configuration in `helm/values.yaml`:**
```yaml
longhorn:
  enabled: false  # Disabled for local

seaweedfs:
  master:
    data:
      storageClass: "csi-hostpath-sc"
  volume:
    dataDirs:
      - storageClass: "csi-hostpath-sc"
  filer:
    data:
      storageClass: "csi-hostpath-sc"
```

**Redis StatefulSet:**
```yaml
volumeClaimTemplates:
  - spec:
      storageClassName: csi-hostpath-sc
```

### Production Deployment

**Storage:**
- StorageClass: `longhorn`
- CSI Driver: `driver.longhorn.io`
- VolumeSnapshotClass: `longhorn-snapshot-vsc` (auto-created by Longhorn)

**Configuration in `helm/values.yaml`:**
```yaml
longhorn:
  enabled: true  # Enabled for production
  defaultSettings:
    defaultDataPath: /var/lib/longhorn
  persistence:
    defaultClass: true
    defaultClassReplicaCount: 3  # Adjust based on cluster size
```

**StorageClass references automatically switch to Longhorn:**
```yaml
{{- if .Values.longhorn.enabled }}
storageClassName: longhorn
{{- else }}
storageClassName: csi-hostpath-sc
{{- end }}
```

## Troubleshooting

### Velero Pod Not Starting

**Check logs:**
```bash
kubectl logs deployment/velero -n celery
```

**Common issues:**
- Missing CSI plugin: Ensure you're not installing the separate CSI plugin (Velero 1.14+ has it built-in)
- Check Velero version: `velero version -n celery`

### BackupStorageLocation Unavailable

**Check BSL status:**
```bash
kubectl get backupstoragelocation -n celery
```

**If Phase is "Unavailable":**
```bash
# Check SeaweedFS S3 pod
kubectl get pods -n celery | grep seaweedfs-s3

# Check S3 service
kubectl get svc -n celery seaweedfs-s3

# Test S3 connectivity
kubectl run -n celery aws-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=accessKey" \
  --env="AWS_SECRET_ACCESS_KEY=secretKey" \
  --env="AWS_DEFAULT_REGION=us-east-1" \
  --command -- aws s3 ls --endpoint-url http://seaweedfs-s3:8333
```

### Backup Stuck in "InProgress"

**Check backup status:**
```bash
velero backup describe <backup-name> -n celery
```

**Check backup logs:**
```bash
velero backup logs <backup-name> -n celery
```

**Common causes:**
- Volume snapshots not completing: `kubectl get volumesnapshot -n celery`
- CSI driver issues: `kubectl get pods -n kube-system | grep csi`

### Volume Snapshots Not Created

**Verify VolumeSnapshotClass exists:**
```bash
kubectl get volumesnapshotclass
```

**For CSI Hostpath (local):**
```
NAME                     DRIVER                DELETIONPOLICY   AGE
csi-hostpath-snapclass   hostpath.csi.k8s.io   Delete           5d
```

**For Longhorn (production):**
```
NAME                     DRIVER                  DELETIONPOLICY   AGE
longhorn-snapshot-vsc    driver.longhorn.io      Delete           5d
```

**Check CSI snapshot controller:**
```bash
kubectl get pods -n kube-system | grep snapshot-controller
```

### Restore Failed

**Check restore status:**
```bash
velero restore describe <restore-name> -n celery --details
```

**Common issues:**
- Resources already exist: Delete the namespace first or use `--namespace-mappings`
- Volume snapshots not ready: Verify snapshots have `READYTOUSE: true`
- CSI driver mismatch: Ensure the same storage driver is used

### Bucket Not Created

**Check bucket-init job logs:**
```bash
# Find the job pod
kubectl get pods -n celery -l app=celery-workflows-velero-bucket-init --sort-by=.metadata.creationTimestamp

# View logs (replace pod name)
kubectl logs <pod-name> -n celery
```

**Manually create bucket:**
```bash
kubectl run -n celery bucket-init --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=accessKey" \
  --env="AWS_SECRET_ACCESS_KEY=secretKey" \
  --env="AWS_DEFAULT_REGION=us-east-1" \
  --command -- aws s3 mb s3://velero-backups \
  --endpoint-url http://seaweedfs-s3:8333
```

## Makefile Reference

All backup operations are available via Makefile targets:

| Target | Description |
|--------|-------------|
| `make csi/install-all` | Install CSI Snapshot CRDs and Controller |
| `make velero/install` | Install Velero server (one-time) |
| `make velero/uninstall` | Uninstall Velero server |
| `make velero/enable` | Enable Velero in chart (BSL + bucket) |
| `make velero/backup` | Create manual backup |
| `make velero/backup-list` | List all backups |
| `make velero/restore BACKUP_NAME=<name>` | Restore from backup |
| `make velero/schedule-enable` | Enable scheduled backups |
| `make velero/schedule-disable` | Disable scheduled backups |

## Configuration Reference

### `helm/values.yaml`

```yaml
velero:
  enabled: false          # Master gate for Velero features
  s3:
    bucket: velero-backups
    accessKey: accessKey   # Must match seaweedfs S3 credentials
    secretKey: secretKey
    region: us-east-1      # Arbitrary, SeaweedFS ignores but AWS SDK requires
  bsl:
    name: seaweedfs-bsl
  schedule:
    enabled: false         # Enable for scheduled backups
    name: celery-daily-backup
    cron: "0 2 * * *"     # Daily at 02:00 UTC
    ttl: 720h             # 30 days retention
```

## Best Practices

1. **Regular Testing:** Periodically test restore operations to verify backup integrity
2. **Retention Policy:** Adjust `ttl` based on compliance and storage capacity requirements
3. **Off-cluster Storage:** For production, consider using an external S3 bucket (AWS S3, MinIO on separate cluster) instead of SeaweedFS
4. **Monitoring:** Set up alerts for backup failures using Velero metrics
5. **Backup Before Changes:** Always create a manual backup before major deployments or configuration changes
6. **Credentials Security:** Rotate S3 credentials regularly and store in a secrets management system

## Additional Resources

- [Velero Documentation](https://velero.io/docs/)
- [CSI Snapshots Documentation](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [SeaweedFS S3 Documentation](https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API)

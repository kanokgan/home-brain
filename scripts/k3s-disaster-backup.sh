#!/bin/bash
#
# K3s Disaster Recovery Backup Script
# Backs up all critical cluster components for full disaster recovery
#
# Usage: Run as root on k3s-master
# Schedule: Daily via CronJob or crontab

set -euo pipefail

# Configuration
BACKUP_ROOT="/mnt/HomeBrain/backups/k3s-snapshots"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$DATE"
LOG_FILE="/var/log/k3s-disaster-backup.log"
RETENTION_DAYS=30

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Starting K3s Disaster Recovery Backup ==="
log "Backup directory: $BACKUP_DIR"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# 1. Backup etcd snapshot or SQLite database (cluster state)
log "Backing up cluster database..."
if k3s etcd-snapshot save --name "k3s-etcd-$DATE" 2>&1 | tee -a "$LOG_FILE"; then
    if [ -f "/var/lib/rancher/k3s/server/db/snapshots/k3s-etcd-$DATE" ]; then
        cp "/var/lib/rancher/k3s/server/db/snapshots/k3s-etcd-$DATE" "$BACKUP_DIR/"
        log "✓ etcd snapshot saved"
    fi
else
    log "⚠ etcd not available, backing up SQLite database instead..."
    if [ -f "/var/lib/rancher/k3s/server/db/state.db" ]; then
        # Stop k3s briefly to get consistent SQLite backup
        systemctl stop k3s
        cp /var/lib/rancher/k3s/server/db/state.db "$BACKUP_DIR/state.db"
        systemctl start k3s
        log "✓ SQLite database backed up"
        # Wait for k3s to be ready
        sleep 5
        until kubectl get nodes &>/dev/null; do sleep 2; done
    else
        log "✗ ERROR: Neither etcd nor SQLite database found"
    fi
fi

# 2. Export all Kubernetes resources
log "Exporting Kubernetes resources..."
kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/all-resources.yaml" 2>&1 | tee -a "$LOG_FILE" || log "Warning: Some resources may have failed"
kubectl get pvc --all-namespaces -o yaml > "$BACKUP_DIR/pvcs.yaml" 2>&1 | tee -a "$LOG_FILE"
kubectl get pv -o yaml > "$BACKUP_DIR/pvs.yaml" 2>&1 | tee -a "$LOG_FILE"
kubectl get configmap --all-namespaces -o yaml > "$BACKUP_DIR/configmaps.yaml" 2>&1 | tee -a "$LOG_FILE"
kubectl get ingress --all-namespaces -o yaml > "$BACKUP_DIR/ingress.yaml" 2>&1 | tee -a "$LOG_FILE" || true
log "✓ Kubernetes resources exported"

# 3. Export secrets (WARNING: Contains sensitive data)
log "Exporting secrets..."
kubectl get secrets --all-namespaces -o yaml > "$BACKUP_DIR/secrets.yaml" 2>&1 | tee -a "$LOG_FILE"
chmod 600 "$BACKUP_DIR/secrets.yaml"
log "✓ Secrets exported (restricted permissions)"

# 4. Export CRDs
log "Exporting Custom Resource Definitions..."
kubectl get crd -o yaml > "$BACKUP_DIR/crds.yaml" 2>&1 | tee -a "$LOG_FILE" || true

# 5. Export ArgoCD applications
log "Exporting ArgoCD applications..."
kubectl get applications -n argocd -o yaml > "$BACKUP_DIR/argocd-applications.yaml" 2>&1 | tee -a "$LOG_FILE" || log "Warning: ArgoCD may not be installed"

# 6. Backup node configuration files
log "Backing up node configuration..."
[ -f /etc/rancher/k3s/config.yaml ] && cp /etc/rancher/k3s/config.yaml "$BACKUP_DIR/k3s-config.yaml"
[ -f /etc/fstab ] && cp /etc/fstab "$BACKUP_DIR/fstab"
[ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl ] && cp /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl "$BACKUP_DIR/containerd-config.toml.tmpl"
[ -f /root/.smbcredentials ] && cp /root/.smbcredentials "$BACKUP_DIR/smbcredentials" && chmod 600 "$BACKUP_DIR/smbcredentials"
log "✓ Node configuration backed up"

# 7. List all PVCs with their host paths
log "Mapping PV to host paths..."
kubectl get pv -o json | jq -r '.items[] | "\(.metadata.name),\(.spec.hostPath.path // "n/a"),\(.spec.capacity.storage)"' > "$BACKUP_DIR/pv-mapping.csv"

# 8. Create manifest for PVC data locations
log "Mapping PVC to PV..."
echo "namespace,pvc-name,pv-name,storage-size" > "$BACKUP_DIR/pvc-mapping.csv"
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
    kubectl get pvc -n "$ns" -o json 2>/dev/null | jq -r ".items[] | \"$ns,\(.metadata.name),\(.spec.volumeName),\(.spec.resources.requests.storage)\"" >> "$BACKUP_DIR/pvc-mapping.csv" || true
done
log "✓ PV/PVC mappings created"

# 9. Export node information
log "Exporting node information..."
kubectl get nodes -o yaml > "$BACKUP_DIR/nodes.yaml"
kubectl describe nodes > "$BACKUP_DIR/nodes-describe.txt"

# 10. Save k3s version
log "Recording k3s version..."
k3s --version > "$BACKUP_DIR/k3s-version.txt"

# 11. Export NVIDIA device plugin config (if exists)
log "Backing up GPU configuration..."
kubectl get configmap nvidia-device-plugin-config -n kube-system -o yaml > "$BACKUP_DIR/nvidia-config.yaml" 2>&1 || log "Info: NVIDIA config not found"

# 12. Create inventory of what's in this backup
log "Creating backup inventory..."
cat > "$BACKUP_DIR/INVENTORY.txt" << EOF
K3s Disaster Recovery Backup
============================
Date: $DATE
Hostname: $(hostname)
K3s Version: $(k3s --version | head -1)

Backup Contents:
- Database: $(ls -lh "$BACKUP_DIR"/k3s-etcd-* "$BACKUP_DIR"/state.db 2>/dev/null | awk '{print $9, $5}' || echo "MISSING")
- Kubernetes resources: $(wc -l < "$BACKUP_DIR/all-resources.yaml") lines
- Secrets: $(grep -c "kind: Secret" "$BACKUP_DIR/secrets.yaml" || echo 0) secrets
- ConfigMaps: $(grep -c "kind: ConfigMap" "$BACKUP_DIR/configmaps.yaml" || echo 0) configmaps
- PVCs: $(tail -n +2 "$BACKUP_DIR/pvc-mapping.csv" | wc -l) persistent volume claims
- PVs: $(tail -n +1 "$BACKUP_DIR/pv-mapping.csv" | wc -l) persistent volumes

Node Configuration:
- k3s config: $([ -f "$BACKUP_DIR/k3s-config.yaml" ] && echo "✓" || echo "✗")
- fstab: $([ -f "$BACKUP_DIR/fstab" ] && echo "✓" || echo "✗")
- containerd config: $([ -f "$BACKUP_DIR/containerd-config.toml.tmpl" ] && echo "✓" || echo "✗")
- SMB credentials: $([ -f "$BACKUP_DIR/smbcredentials" ] && echo "✓" || echo "✗")

ArgoCD Applications: $(grep -c "kind: Application" "$BACKUP_DIR/argocd-applications.yaml" 2>/dev/null || echo 0)

Total backup size: $(du -sh "$BACKUP_DIR" | awk '{print $1}')
EOF

log "✓ Inventory created"

# 13. Create restore instructions
log "Creating restore instructions..."
cat > "$BACKUP_DIR/RESTORE.md" << 'EOF'
# K3s Disaster Recovery - Restore Instructions

## Overview
This backup was created from a running k3s cluster and contains everything needed for complete disaster recovery.

## Prerequisites

Before starting restoration:

1. **Fresh Ubuntu installation** on k3s-master node
2. **Same hostname** as original (or update /etc/hosts)
3. **Tailscale installed** and joined to network
4. **NAS accessible** at /mnt/HomeBrain
5. **Root access** to the node

## Restore Procedure

### Step 1: Restore Node Configuration

```bash
# Mount NAS
sudo mkdir -p /mnt/HomeBrain
# Add to /etc/fstab (copy from backup if available)
sudo cp RESTORE_DIR/fstab /etc/fstab
sudo mount -a

# Restore SMB credentials
sudo cp RESTORE_DIR/smbcredentials /root/.smbcredentials
sudo chmod 600 /root/.smbcredentials

# Verify NAS mounts
df -h | grep /mnt
```

### Step 2: Prepare k3s Configuration

```bash
# Create k3s config directory
sudo mkdir -p /etc/rancher/k3s

# Restore k3s configuration
sudo cp RESTORE_DIR/k3s-config.yaml /etc/rancher/k3s/config.yaml

# Review and update if needed (check IPs, interface names)
sudo nano /etc/rancher/k3s/config.yaml
```

### Step 3: Install k3s (DO NOT START YET)

Check k3s-version.txt for the exact version to install:

```bash
# Install specific k3s version from backup
VERSION=$(cat RESTORE_DIR/k3s-version.txt | grep -oP 'v\d+\.\d+\.\d+\+k3s\d+' | head -1)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$VERSION INSTALL_K3S_SKIP_START=true sh -

# Verify installation
k3s --version
```

### Step 4: Restore etcd Snapshot

```bash
# Copy etcd snapshot to k3s snapshots directory
sudo mkdir -p /var/lib/rancher/k3s/server/db/snapshots
sudo cp RESTORE_DIR/k3s-etcd-* /var/lib/rancher/k3s/server/db/snapshots/

# Get snapshot name
SNAPSHOT_NAME=$(basename RESTORE_DIR/k3s-etcd-*)

# Restore from snapshot (this starts k3s in restore mode)
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/$SNAPSHOT_NAME

# Wait for restore to complete (watch for "Managed etcd cluster membership has been reset" message)
# Then Ctrl+C to stop

# Start k3s normally
sudo systemctl start k3s
sudo systemctl enable k3s

# Wait for k3s to be ready
sudo k3s kubectl get nodes
```

### Step 5: Restore GPU Configuration (if applicable)

```bash
# Restore containerd config for NVIDIA runtime
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/
sudo cp RESTORE_DIR/containerd-config.toml.tmpl \
  /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl

# Restart k3s to apply
sudo systemctl restart k3s

# Verify GPU config
sudo k3s kubectl get nodes -o json | jq '.items[0].status.allocatable | {"nvidia.com/gpu"}'
```

### Step 6: Verify Cluster State

```bash
# Check all namespaces
sudo k3s kubectl get namespaces

# Check pods across all namespaces
sudo k3s kubectl get pods --all-namespaces

# Check PVCs
sudo k3s kubectl get pvc --all-namespaces

# Check secrets
sudo k3s kubectl get secrets --all-namespaces
```

### Step 7: Restore PVC Data

The etcd restore brings back PVC/PV definitions, but not the actual data.

**Review the PVC mappings:**
```bash
cat RESTORE_DIR/pvc-mapping.csv
cat RESTORE_DIR/pv-mapping.csv
```

**For each PVC, restore data from NAS backups:**

```bash
# Example: Restore Immich library
# Find the PV path from pv-mapping.csv
PV_PATH="/var/lib/rancher/k3s/storage/pvc-xxxxx_immich_immich-library-pvc"

# Restore from NAS backup
sudo rsync -av --progress \
  /mnt/HomeBrain/backups/immich-library/ \
  $PV_PATH/

# Fix permissions (uid 999 = postgres/immich user)
sudo chown -R 999:999 $PV_PATH/
```

**Repeat for other critical PVCs:**
- ArgoCD state
- Monitoring data (if needed)
- Actual Budget database
- Any other application data

### Step 8: Restart Affected Pods

After restoring PVC data, restart pods to pick up the data:

```bash
# Restart all pods in a namespace
sudo k3s kubectl rollout restart deployment -n immich
sudo k3s kubectl rollout restart statefulset -n monitoring

# Or delete pods to force recreation
sudo k3s kubectl delete pods --all -n <namespace>
```

### Step 9: Verify Applications

```bash
# Check ArgoCD
sudo k3s kubectl get applications -n argocd

# Check Immich
sudo k3s kubectl get pods -n immich

# Check monitoring
sudo k3s kubectl get pods -n monitoring

# Access services via Tailscale or Cloudflare Tunnel
```

## Troubleshooting

### etcd Restore Failed

If `k3s server --cluster-reset` fails:

```bash
# Clean up and try again
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s/server/db/
sudo k3s server --cluster-reset --cluster-reset-restore-path=<snapshot-path>
```

### Pods Stuck in Pending

Check PVC status:
```bash
sudo k3s kubectl get pvc --all-namespaces
sudo k3s kubectl describe pvc <pvc-name> -n <namespace>
```

Verify PV data exists at hostPath.

### Secrets Missing

If secrets didn't restore from etcd:
```bash
sudo k3s kubectl apply -f RESTORE_DIR/secrets.yaml
```

### GPU Not Working

Re-deploy NVIDIA device plugin:
```bash
sudo k3s kubectl apply -f RESTORE_DIR/nvidia-config.yaml
sudo k3s kubectl apply -f <path-to-gpu-manifests>
```

## Post-Restore Checklist

- [ ] All namespaces present
- [ ] All pods running
- [ ] PVCs bound and data accessible
- [ ] Secrets restored
- [ ] ConfigMaps present
- [ ] Ingress/Services working
- [ ] GPU detected (if applicable)
- [ ] External storage (NAS) mounted
- [ ] Tailscale connectivity working
- [ ] ArgoCD syncing applications
- [ ] Monitoring stack operational
- [ ] Application data verified (check databases, uploads, etc.)

## Reference Files

- `INVENTORY.txt` - Backup contents summary
- `pvc-mapping.csv` - PVC to PV mappings
- `pv-mapping.csv` - PV to host path mappings
- `k3s-version.txt` - Original k3s version
- `nodes-describe.txt` - Node details from backup time
EOF

log "✓ Restore instructions created"

# 14. Create metadata file
cat > "$BACKUP_DIR/metadata.json" << EOF
{
  "backup_date": "$DATE",
  "hostname": "$(hostname)",
  "k3s_version": "$(k3s --version | head -1)",
  "backup_type": "full-disaster-recovery",
  "retention_days": $RETENTION_DAYS
}
EOF

# 15. Set appropriate permissions
chmod -R 700 "$BACKUP_DIR"
chmod 600 "$BACKUP_DIR/secrets.yaml" "$BACKUP_DIR/smbcredentials" 2>/dev/null || true

log "Setting backup permissions..."

# 16. Create latest symlink
log "Creating latest symlink..."
rm -f "$BACKUP_ROOT/latest" 2>/dev/null || true
if ln -sfn "$BACKUP_DIR" "$BACKUP_ROOT/latest" 2>/dev/null; then
    log "✓ Latest symlink created"
else
    log "⚠ Warning: Could not create symlink (NAS limitation), skipping..."
fi

# 17. Cleanup old backups
log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "202*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>&1 | tee -a "$LOG_FILE"

# 18. Calculate final size and summary
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
log "✓ Backup completed successfully"
log "Backup size: $BACKUP_SIZE"
log "Location: $BACKUP_DIR"
log "=== K3s Disaster Recovery Backup Complete ==="

# Display summary
cat "$BACKUP_DIR/INVENTORY.txt"

exit 0

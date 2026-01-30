# K3s Disaster Recovery

## Overview

Complete disaster recovery strategy for the home-brain k3s cluster. This covers catastrophic failures requiring full cluster rebuild, including hardware failure, accidental `k3s-uninstall.sh`, corrupted etcd, or CNI disasters.

**Recovery Time Objective (RTO):** 2-4 hours  
**Recovery Point Objective (RPO):** 24 hours (daily backups at 3 AM)

## What Gets Backed Up

### Automatic Daily Backups (3 AM Thailand Time)

| Component | Location | Retention | Backup Method |
|-----------|----------|-----------|---------------|
| **etcd database** | `/mnt/HomeBrain/backups/k3s-snapshots/` | 30 days | k3s etcd-snapshot |
| **All Kubernetes resources** | Same | 30 days | kubectl export YAML |
| **Secrets** | Same (encrypted at rest) | 30 days | kubectl export YAML |
| **Node configuration** | Same | 30 days | File copy |
| **PVC mappings** | Same | 30 days | Generated CSV |
| **Immich library data** | `/mnt/HomeBrain/backups/immich-library/` | Indefinite | rsync (2 AM) |

### What's NOT Automatically Backed Up

- **Ephemeral pod data** (logs, temporary files)
- **Container images** (pull from registries during restore)
- **PVC data** except Immich (manual restore from application-specific backups)

## Backup Strategy

### Automated Backup Components

**1. Cluster State (etcd)**
- Snapshots entire Kubernetes state
- Includes: deployments, services, ConfigMaps, secrets, RBAC, CRDs
- Stored: `/mnt/HomeBrain/backups/k3s-snapshots/<date>/k3s-etcd-<date>`

**2. Resource Manifests**
- YAML exports of all resources (human-readable backup)
- Useful if etcd restore fails
- Can selectively restore individual resources

**3. Node Configuration**
- `/etc/rancher/k3s/config.yaml` - k3s settings
- `/etc/fstab` - NAS mounts
- `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` - GPU runtime
- `/root/.smbcredentials` - NAS credentials

**4. PV/PVC Mappings**
- CSV files mapping PVCs to host paths
- Critical for restoring application data to correct locations

### Backup Schedule

```
02:00 - Immich library rsync to NAS
03:00 - Full k3s disaster recovery backup
```

## Deployment

### Step 1: Prepare NAS Directory

On k3s-master:

```bash
# Verify NAS mount
ls -la /mnt/HomeBrain/backups/

# Create backup directory (should already exist from user setup)
sudo mkdir -p /mnt/HomeBrain/backups/k3s-snapshots
sudo chmod 755 /mnt/HomeBrain/backups/k3s-snapshots

# Test write access
sudo touch /mnt/HomeBrain/backups/k3s-snapshots/test
sudo rm /mnt/HomeBrain/backups/k3s-snapshots/test
```

### Step 2: Deploy Backup Script to k3s-master

```bash
# Copy backup script to k3s-master
scp scripts/k3s-disaster-backup.sh kanokgan@k3s-master.dove-komodo.ts.net:/tmp/

# SSH to k3s-master
ssh kanokgan@k3s-master.dove-komodo.ts.net

# Move script to /root/scripts
sudo mkdir -p /root/scripts
sudo mv /tmp/k3s-disaster-backup.sh /root/scripts/
sudo chmod +x /root/scripts/k3s-disaster-backup.sh
sudo chown root:root /root/scripts/k3s-disaster-backup.sh
```

### Step 3: Test Backup Manually

```bash
# Run first backup manually to verify
sudo /root/scripts/k3s-disaster-backup.sh

# Check results
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/latest/
cat /mnt/HomeBrain/backups/k3s-snapshots/latest/INVENTORY.txt
cat /var/log/k3s-disaster-backup.log
```

### Step 4: Deploy CronJob (Alternative to Cron)

**Option A: Kubernetes CronJob (Recommended)**

```bash
# Load backup script into ConfigMap
kubectl create configmap k3s-disaster-backup-script \
  -n kube-system \
  --from-file=k3s-disaster-backup.sh=./scripts/k3s-disaster-backup.sh

# Deploy CronJob
kubectl apply -f k8s/backup/k3s-disaster-backup-cronjob.yaml

# Verify
kubectl get cronjob -n kube-system k3s-disaster-backup
kubectl get pods -n kube-system -l app=k3s-disaster-backup
```

**Option B: Traditional Crontab**

```bash
# Add to root crontab on k3s-master
sudo crontab -e

# Add this line:
0 3 * * * /root/scripts/k3s-disaster-backup.sh >> /var/log/k3s-disaster-backup.log 2>&1
```

### Step 5: Monitor Backups

```bash
# Check latest backup
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/latest/

# View backup log
tail -f /var/log/k3s-disaster-backup.log

# List all backups
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/

# Check CronJob status (if using Kubernetes CronJob)
kubectl get cronjob -n kube-system k3s-disaster-backup
kubectl logs -n kube-system -l app=k3s-disaster-backup --tail=100
```

## Disaster Recovery Procedures

### Scenario 1: Complete Cluster Loss

**Situation:** k3s-master hardware failure, OS corruption, or accidental `k3s-uninstall.sh`

**Prerequisites:**
- Fresh Ubuntu installation on k3s-master (or replacement hardware)
- Same hostname as original: `k3s-master`
- Tailscale installed and connected
- NAS accessible at 192.168.0.243

**Recovery Steps:**

1. **Identify latest backup:**
```bash
# On any machine with NAS access
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/
RESTORE_DIR="/mnt/HomeBrain/backups/k3s-snapshots/latest"
```

2. **Follow restore instructions:**
```bash
# On k3s-master (after OS reinstall)
sudo mkdir -p /mnt/HomeBrain
sudo mount -t cifs //192.168.0.243/HomeBrain /mnt/HomeBrain -o credentials=/tmp/creds

# Follow detailed steps in:
cat $RESTORE_DIR/RESTORE.md
```

3. **Key steps summary:**
   - Restore node configuration (fstab, k3s config, SMB creds)
   - Install k3s with same version
   - Restore etcd snapshot
   - Apply GPU configuration
   - Verify cluster state
   - Restore PVC data from NAS
   - Restart affected pods

**Expected Time:** 2-4 hours (depending on data restoration size)

### Scenario 2: Partial Data Loss (PVCs Only)

**Situation:** Accidental PVC deletion, corrupted volume

**Recovery:**

```bash
# Check PVC mapping from latest backup
cat /mnt/HomeBrain/backups/k3s-snapshots/latest/pvc-mapping.csv | grep <namespace>

# Restore specific PVC data
# Example: Immich
sudo rsync -av /mnt/HomeBrain/backups/immich-library/ \
  /var/lib/rancher/k3s/storage/pvc-<id>_immich_immich-library-pvc/

# Fix permissions
sudo chown -R 999:999 /var/lib/rancher/k3s/storage/pvc-<id>_immich_immich-library-pvc/

# Restart pods
kubectl rollout restart deployment/immich-server -n immich
```

### Scenario 3: Secrets Lost

**Situation:** Secrets accidentally deleted or corrupted

**Recovery:**

```bash
# Restore all secrets
RESTORE_DIR="/mnt/HomeBrain/backups/k3s-snapshots/latest"
kubectl apply -f $RESTORE_DIR/secrets.yaml

# Or restore specific namespace secrets
kubectl get secret -n <namespace> -o yaml < $RESTORE_DIR/secrets.yaml | kubectl apply -f -
```

### Scenario 4: etcd Corruption

**Situation:** etcd database corrupted but node is healthy

**Recovery:**

```bash
# Stop k3s
sudo systemctl stop k3s

# Backup current corrupt state (just in case)
sudo mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db.corrupt

# Restore from snapshot
RESTORE_DIR="/mnt/HomeBrain/backups/k3s-snapshots/latest"
SNAPSHOT=$(basename $RESTORE_DIR/k3s-etcd-*)

sudo cp $RESTORE_DIR/$SNAPSHOT /var/lib/rancher/k3s/server/db/snapshots/

sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/$SNAPSHOT

# Start k3s normally
sudo systemctl start k3s
```

### Scenario 5: CNI Network Disaster (The Classic)

**Situation:** CNI broken (usually from nvidia-ctk misconfiguration)

**Symptoms:**
- Pods stuck in ContainerCreating
- No pod-to-pod networking
- `kubectl logs` fails

**Recovery:**

```bash
# Full k3s reinstall required
sudo /usr/local/bin/k3s-uninstall.sh

# Then follow Scenario 1 (Complete Cluster Loss)
# Key: Restore containerd config.toml.tmpl BEFORE starting k3s
```

## Testing & Validation

### Monthly Backup Verification

Run this checklist monthly:

```bash
# 1. Verify backups exist
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/ | tail -5

# 2. Check latest backup completeness
LATEST="/mnt/HomeBrain/backups/k3s-snapshots/latest"
cat $LATEST/INVENTORY.txt

# 3. Verify etcd snapshot integrity
k3s etcd-snapshot ls

# 4. Test secrets decryption (if encrypted)
kubectl get secret -n kube-system -o yaml | head

# 5. Check backup logs for errors
tail -100 /var/log/k3s-disaster-backup.log | grep -i error

# 6. Verify NAS connectivity
timeout 5 ls /mnt/HomeBrain/backups/ || echo "NAS UNREACHABLE!"
```

### Quarterly DR Drill (Recommended)

**Test restore procedure on a VM or spare hardware:**

1. Install Ubuntu on test machine
2. Follow complete restore procedure from latest backup
3. Verify cluster functionality
4. Document time taken and any issues
5. Update runbook with lessons learned

## Monitoring & Alerts

### Backup Success Monitoring

**Check backup job status:**

```bash
# Via CronJob
kubectl get cronjobs -n kube-system k3s-disaster-backup
kubectl get jobs -n kube-system | grep k3s-disaster-backup

# Via log file
grep "Backup completed successfully" /var/log/k3s-disaster-backup.log | tail -5
```

**Set up alerts (manual check for now):**

- [ ] Daily: Verify backup exists in `/mnt/HomeBrain/backups/k3s-snapshots/`
- [ ] Weekly: Check backup size consistency
- [ ] Monthly: Review INVENTORY.txt for completeness

### Backup Failure Troubleshooting

**Backup job fails:**

```bash
# Check CronJob status
kubectl describe cronjob k3s-disaster-backup -n kube-system

# Check recent job logs
kubectl logs -n kube-system -l app=k3s-disaster-backup --tail=200

# Check system log
sudo tail -200 /var/log/k3s-disaster-backup.log

# Common issues:
# - NAS mount failed: Check /etc/fstab and mount status
# - Permission denied: Check /mnt/HomeBrain/backups/k3s-snapshots/ permissions
# - etcd snapshot failed: Check k3s service status
```

**NAS unreachable:**

```bash
# Check mount
df -h | grep HomeBrain

# Remount if needed
sudo umount /mnt/HomeBrain
sudo mount -a

# Check SMB credentials
sudo cat /root/.smbcredentials
```

## Backup Storage Requirements

### Current Usage

```bash
# Check backup sizes
du -sh /mnt/HomeBrain/backups/k3s-snapshots/*
du -sh /mnt/HomeBrain/backups/immich-library/
```

**Typical sizes (your setup):**
- etcd snapshot: ~100-500 MB
- Resource manifests: ~5-10 MB
- Total per backup: ~500 MB
- 30 days retention: ~15 GB

**Immich library:**
- Current: ~1.7 TB
- Growing: ~50-100 GB/month

### NAS Capacity Planning

**Minimum requirements:**
- k3s snapshots: 20 GB (30 days)
- Immich library: 2 TB (current + growth)
- Buffer: 500 GB
- **Total: 2.5 TB**

## Security Considerations

### Secrets in Backups

**⚠️ CRITICAL:** Backups contain unencrypted secrets!

**Current protection:**
- File permissions: `chmod 600` on secrets.yaml
- Directory permissions: `chmod 700` on backup directory
- NAS access control: Only accessible from k3s-master

**Recommended enhancements:**
- [ ] Encrypt secrets.yaml with GPG before storing on NAS
- [ ] Use separate encrypted volume for secrets backups
- [ ] Implement backup integrity verification (checksums)

### Access Control

**Who can restore:**
- Root access on k3s-master
- NAS access credentials
- Kubernetes admin kubeconfig

**Audit trail:**
- Backup logs in `/var/log/k3s-disaster-backup.log`
- NAS file access logs (if enabled)

## Related Documentation

- [Infrastructure Setup](01-infrastructure.md)
- [GPU Configuration](03-gpu-configuration.md)
- [Immich Database Restore](10-immich-database-restore.md)
- Kubernetes Backup Best Practices: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster

## Maintenance

### Updating Backup Script

When modifying the backup script:

```bash
# 1. Edit script locally
vim scripts/k3s-disaster-backup.sh

# 2. Test on k3s-master
scp scripts/k3s-disaster-backup.sh kanokgan@k3s-master:/tmp/
ssh kanokgan@k3s-master "sudo cp /tmp/k3s-disaster-backup.sh /root/scripts/ && sudo /root/scripts/k3s-disaster-backup.sh"

# 3. Update ConfigMap (if using CronJob)
kubectl create configmap k3s-disaster-backup-script \
  -n kube-system \
  --from-file=k3s-disaster-backup.sh=./scripts/k3s-disaster-backup.sh \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Commit to git
git add scripts/k3s-disaster-backup.sh
git commit -m "Update disaster recovery backup script"
```

### Retention Policy Changes

To change backup retention (default 30 days):

```bash
# Edit script
vim scripts/k3s-disaster-backup.sh
# Change: RETENTION_DAYS=30

# Redeploy (see above)
```

## Lessons Learned

### From January 2026 CNI Disaster

**What went wrong:**
1. Ran `nvidia-ctk runtime configure` on k3s node
2. Overwrote k3s containerd config
3. CNI plugins broke, entire cluster unusable
4. Had to run `k3s-uninstall.sh` (lost all data)

**What we lost:**
- All PVC data (1.7TB Immich library)
- All Kubernetes secrets
- All ConfigMaps
- RBAC configurations
- ArgoCD state

**What saved us:**
- NAS rsync backup of Immich library
- Git repository with all manifests
- Immich's automatic database backups (in library PVC)

**What we improved:**
- Created this comprehensive disaster recovery solution
- Automated etcd snapshots
- Documented GPU configuration properly
- Added secrets backup
- Created detailed restore procedures

**Prevention:**
- ⚠️ **NEVER run nvidia-ctk on k3s nodes**
- Always test configuration changes in VMs first
- Keep documentation updated
- Run monthly backup verification

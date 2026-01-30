# Scripts Directory

Operational scripts for the home-brain k3s cluster.

## Disaster Recovery

### k3s-disaster-backup.sh

**Purpose:** Complete disaster recovery backup for k3s cluster

**What it backs up:**
- etcd database snapshot (cluster state)
- All Kubernetes resources (YAML manifests)
- All secrets (with restricted permissions)
- Node configuration files (k3s config, fstab, GPU config)
- PV/PVC mappings
- ArgoCD applications

**Schedule:** Daily at 3 AM via CronJob or crontab  
**Retention:** 30 days  
**Storage:** `/mnt/HomeBrain/backups/k3s-snapshots/`  
**Log:** `/var/log/k3s-disaster-backup.log`

**Deployment:**
See [docs/runbooks/11-disaster-recovery-QUICKSTART.md](../docs/runbooks/11-disaster-recovery-QUICKSTART.md)

**Restore:**
See `/mnt/HomeBrain/backups/k3s-snapshots/latest/RESTORE.md` after disaster

## Media Conversion

### convert-ts-to-mp4.sh

**Purpose:** Convert .ts video files to .mp4 for Jellyfin compatibility

**Usage:**
```bash
./scripts/convert-ts-to-mp4.sh /path/to/video.ts
```

**Features:**
- Uses ffmpeg with GPU acceleration (if available)
- Maintains video quality
- Preserves original timestamps
- Creates backup of original file

## Adding New Scripts

When adding operational scripts:

1. Place in this directory
2. Make executable: `chmod +x script.sh`
3. Add shebang: `#!/bin/bash`
4. Add header comments explaining purpose and usage
5. Document in this README
6. If deploying to k3s nodes, document in relevant runbook

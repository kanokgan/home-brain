# Immich Database Restore

## Overview

This guide covers restoring Immich's Postgres database from automatic backups stored in the library PVC.

## Backup Information

**Location:** `/usr/src/app/upload/backups/` (inside immich-server pod)  
**Physical Path:** `/var/lib/rancher/k3s/storage/pvc-xxx_immich_immich-library-pvc/backups/` (on k3s-master)  
**Format:** gzipped SQL dumps  
**Naming:** `immich-db-backup-YYYYMMDDTHHMMSS-vX.Y.Z-pg14.19.sql.gz`  
**Frequency:** Daily at midnight (automated by Immich)  
**Retention:** 31 days

### Backup Contents

Each backup includes:
- User accounts and authentication
- Asset metadata (224k+ assets in our case)
- Albums and album-asset relationships (38 albums, 8,746 relationships)
- Face recognition data (200k+ faces)
- Smart search embeddings (CLIP vectors)
- System configuration and settings
- Shared links and permissions
- Activity logs

### What's NOT in Database Backups

- Original photos/videos (stored in `library/` directory)
- Generated thumbnails (stored in `thumbs/` directory)
- Encoded videos (stored in `encoded-video/` directory)
- ML model files (cached separately)

## Prerequisites

Before restoring:

1. **Immich pods running:**
```bash
kubectl get pods -n immich
# Need: immich-postgres (1/1 Running)
# Need: immich-server (2/2 Running) for backup access
```

2. **Identify backup to restore:**
```bash
kubectl exec -n immich deployment/immich-server -c immich-server -- \
  ls -lh /usr/src/app/upload/backups/
```

Look for latest or specific date backup (format: `immich-db-backup-20260130T000000-v2.5.0-pg14.19.sql.gz`)

## Restore Procedure

### 1. Stop Immich Services (Optional but Recommended)

```bash
# Scale down Immich server and ML to prevent concurrent access
kubectl scale deployment/immich-server -n immich --replicas=0
kubectl scale deployment/immich-machine-learning -n immich --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod -n immich -l app=immich-server --timeout=60s
```

### 2. Restore Database

Choose the backup file to restore (use latest for most recent data):

```bash
# Set backup filename
BACKUP_FILE="immich-db-backup-20260130T000000-v2.5.0-pg14.19.sql.gz"

# Restore database
kubectl exec -n immich deployment/immich-server -c immich-server -- \
  sh -c "gunzip -c /usr/src/app/upload/backups/$BACKUP_FILE" | \
  kubectl exec -i -n immich deployment/immich-postgres -- \
  psql -U immich -d immich
```

**Expected output:**
- Lots of `SET`, `DROP`, `CREATE` statements
- Some `ERROR: role "postgres" does not exist` messages (safe to ignore - ownership metadata)
- `COPY XXXXX` lines showing data rows imported
- `CREATE INDEX` and clustering operations at the end
- Exit code 0 means success

**Time:** ~2-5 minutes for typical database (depends on size)

### 3. Start Immich Services

```bash
kubectl scale deployment/immich-server -n immich --replicas=1
kubectl scale deployment/immich-machine-learning -n immich --replicas=1

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -n immich -l app=immich-server --timeout=120s
kubectl wait --for=condition=ready pod -n immich -l app=immich-machine-learning --timeout=120s
```

### 4. Verify Restoration

Check database contents:

```bash
# Check asset count
kubectl exec -n immich deployment/immich-postgres -- \
  psql -U immich -d immich -c "SELECT COUNT(*) FROM asset;"

# Check user count
kubectl exec -n immich deployment/immich-postgres -- \
  psql -U immich -d immich -c "SELECT COUNT(*) FROM \"user\";"

# Check album count
kubectl exec -n immich deployment/immich-postgres -- \
  psql -U immich -d immich -c "SELECT COUNT(*) FROM album;"

# Check face count
kubectl exec -n immich deployment/immich-postgres -- \
  psql -U immich -d immich -c "SELECT COUNT(*) FROM person;"
```

Check Immich server logs for errors:

```bash
kubectl logs -n immich deployment/immich-server -c immich-server --tail=50
```

### 5. Regenerate Thumbnails (If Needed)

If thumbnails are missing or corrupt after restore:

1. Access Immich web interface
2. Go to **Administration** → **Jobs**
3. Queue these jobs:
   - **Thumbnail Generation** → Queue All
   - **Video Transcoding** → Queue All (if videos exist)

Or trigger via API:

```bash
# Get API key from Immich UI first

curl -X POST "https://immich.your-domain.com/api/jobs/thumbnail-generation" \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"force": true}'
```

**Note:** With 224k+ assets, thumbnail generation takes several hours (can run overnight).

## Version Compatibility

### Database Version Mismatches

Immich backups include version info in filename: `immich-db-backup-YYYYMMDDTHHMMSS-vX.Y.Z-pgNN.sql.gz`

**Safe to restore:**
- Same major.minor version (e.g., v2.5.0 → v2.5.2)
- Usually safe: One minor version back (e.g., v2.4.x → v2.5.x)

**May cause issues:**
- Major version jumps (e.g., v1.x → v2.x)
- Postgres version mismatch (our cluster uses Postgres 14.19)

**Best practice:** Restore backup from same or close Immich version. Immich will auto-migrate schema on startup if needed.

### Post-Restore Migration

After restoring an older backup, Immich will:
1. Detect schema version mismatch
2. Run database migrations automatically
3. Log migration progress in immich-server logs

Monitor migrations:

```bash
kubectl logs -n immich deployment/immich-server -c immich-server -f | grep -i migration
```

## Troubleshooting

### "role 'postgres' does not exist" Errors

**Symptoms:** Multiple errors during restore about postgres role

**Cause:** Backup includes ownership metadata for "postgres" user, but our Postgres uses "immich" user

**Impact:** None - these are non-critical ownership errors

**Solution:** Ignore these errors. Data and structure restore successfully.

### "relation already exists" Errors

**Cause:** Restoring to non-empty database

**Solution:** Clear database first (destructive):

```bash
kubectl exec -n immich deployment/immich-postgres -- \
  psql -U immich -d postgres -c "DROP DATABASE immich;"

kubectl exec -n immich deployment/immich-postgres -- \
  psql -U immich -d postgres -c "CREATE DATABASE immich OWNER immich;"

# Then retry restore
```

### Immich Shows "No Assets" After Restore

**Likely causes:**

1. **Thumbnails missing:**
   - Database restored but thumbnails not generated
   - Solution: Queue thumbnail generation jobs (see step 5)

2. **Library path mismatch:**
   - Check asset paths in database match actual files
   ```bash
   kubectl exec -n immich deployment/immich-postgres -- \
     psql -U immich -d immich -c "SELECT \"originalPath\" FROM asset LIMIT 5;"
   ```
   - Verify files exist at those paths

3. **Version incompatibility:**
   - Check Immich server logs for migration errors
   - May need to restore from newer backup

### Cannot Access Backup Files

**Error:** `No such file or directory: /usr/src/app/upload/backups/`

**Cause:** Library PVC not mounted or backup directory doesn't exist

**Solutions:**

1. Check PVC mount:
```bash
kubectl exec -n immich deployment/immich-server -c immich-server -- \
  ls -la /usr/src/app/upload/
```

2. Check backup location on host:
```bash
ssh kanokgan@k3s-master.dove-komodo.ts.net
sudo ls -lh /var/lib/rancher/k3s/storage/pvc-*_immich_immich-library-pvc/backups/
```

3. Backups may be on NAS:
```bash
ls -lh /mnt/HomeBrain/backups/immich-library/backups/
```

## Manual Backup Creation

To create an ad-hoc backup before major changes:

```bash
# Generate timestamp
TIMESTAMP=$(date +%Y%m%dT%H%M%S)

# Create backup
kubectl exec -n immich deployment/immich-postgres -- \
  pg_dump -U immich -d immich -F c -b -v -f /tmp/manual-backup-$TIMESTAMP.dump

# Copy backup out
kubectl cp immich/immich-postgres-xxx:/tmp/manual-backup-$TIMESTAMP.dump \
  ./manual-backup-$TIMESTAMP.dump
```

Or use Immich's built-in backup (creates in library PVC):

```bash
# Trigger via API (requires API key)
curl -X POST "https://immich.your-domain.com/api/database/backup" \
  -H "X-Api-Key: YOUR_API_KEY"
```

## Restoration Scenarios

### Scenario 1: Accidental Deletion Recovery

User accidentally deleted photos/albums:

1. Identify backup from before deletion
2. Follow restore procedure
3. Thumbnails may need regeneration if old

### Scenario 2: Cluster Rebuild

After k3s reinstall (e.g., CNI disaster):

1. Restore library PVC data from NAS
2. Deploy Immich pods
3. Restore database (this procedure)
4. Regenerate thumbnails (will take hours)
5. Albums, faces, search data fully restored

### Scenario 3: Version Upgrade Rollback

Immich upgrade caused issues:

1. Scale down Immich to 0 replicas
2. Restore backup from before upgrade
3. Downgrade Immich image version
4. Scale back up

**Note:** Schema downgrades not officially supported but usually works for minor versions.

### Scenario 4: Database Corruption

Postgres corruption or inconsistency:

1. Stop Immich services
2. Restore from latest good backup
3. Restart services
4. Monitor for errors

## Backup Verification

Periodically test backup integrity:

```bash
# Test latest backup can be read
LATEST_BACKUP=$(kubectl exec -n immich deployment/immich-server -c immich-server -- \
  ls -t /usr/src/app/upload/backups/ | head -1)

kubectl exec -n immich deployment/immich-server -c immich-server -- \
  gunzip -t /usr/src/app/upload/backups/$LATEST_BACKUP

echo "Exit code $? (0 = valid gzip file)"
```

## Related Documentation

- [Immich Deployment](04-immich-deployment.md)
- [Infrastructure Setup](01-infrastructure.md)
- Immich Backup Documentation: https://immich.app/docs/administration/backup

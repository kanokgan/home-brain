# Immich Storage Migration Plan
**Created**: June 2, 2026
**Status**: Ready to execute (waiting for user confirmation)

## Objective
Split Immich storage to keep performance-critical data on SSD and move large original files to NAS.

## Current State
- **Total Immich usage**: 1.2TB on main SSD (75% of 1.9TB)
- **Breakdown**:
  - `library/` (originals): 957GB ← **MOVE TO NAS**
  - `encoded-video/` (transcoded): 150GB ← **KEEP ON SSD**
  - `thumbs/` (thumbnails): 53GB ← **KEEP ON SSD**
  - `backups/` (database): 28GB ← **KEEP ON SSD**
  - `upload/` (staging): 34MB ← **KEEP ON SSD**

## Target State
- **SSD** (~231GB): thumbs + encoded-video + backups + upload
- **NAS** (957GB): library (original photos/videos)
- **Space saved on SSD**: ~957GB (will have 1.4TB free!)

## Available NAS Shares
- `//192.168.0.243/CameraUploads` (14TB, 3.1TB free)
- `//192.168.0.243/Nrop` (14TB, 3.1TB free)
- All other drives (JongdeeDrive, ChurinDrive, etc.)

## Prerequisites (User to decide)
1. **Which NAS share?** User needs to choose which share to use
2. **Path on NAS?** Suggested: `/mnt/Nrop/immich-library/` or `/mnt/CameraUploads/immich-library/`
3. **Migration window?** Will need 4-6 hours for 957GB copy + brief Immich downtime

## Migration Steps

### Phase 1: Prepare NAS Storage
```bash
# SSH to k3s-master
ssh kanokgan@k3s-master

# Create directory on NAS (example using Nrop)
sudo mkdir -p /mnt/Nrop/immich-library
sudo chown 1000:1000 /mnt/Nrop/immich-library

# Verify NAS is writable
touch /mnt/Nrop/immich-library/test.txt
rm /mnt/Nrop/immich-library/test.txt
```

### Phase 2: Copy Library Data to NAS
```bash
# Find the actual PVC path
kubectl get pv | grep immich-library

# Example path: /var/lib/rancher/k3s/storage/pvc-5b5c0942-9cac-49c8-9a98-c86f0dfe9b1b_immich_immich-library-pvc

# Copy library directory to NAS (will take hours)
sudo rsync -avh --progress \
  /var/lib/rancher/k3s/storage/pvc-5b5c0942-9cac-49c8-9a98-c86f0dfe9b1b_immich_immich-library-pvc/library/ \
  /mnt/Nrop/immich-library/

# Verify copy
sudo du -sh /mnt/Nrop/immich-library/
# Should show ~957GB
```

### Phase 3: Update Kubernetes Configuration

#### 3a. Add NAS hostPath volume to server.yaml
Add new volume mount to `/usr/src/app/upload/library` pointing to NAS:

```yaml
# In k8s/immich/server.yaml
spec:
  containers:
  - name: immich-server
    volumeMounts:
    - name: library
      mountPath: /usr/src/app/upload
    - name: library-nas  # NEW
      mountPath: /usr/src/app/upload/library  # NEW - overwrites library subdirectory
    # ... other mounts ...
  
  volumes:
  - name: library
    persistentVolumeClaim:
      claimName: immich-library-pvc
  - name: library-nas  # NEW
    hostPath:
      path: /mnt/Nrop/immich-library
      type: Directory
```

### Phase 4: Apply Changes
```bash
# From Mac
cd /Users/kanokgan/Developer/personal/home-brain

# Apply updated configuration
kubectl apply -f k8s/immich/server.yaml

# Wait for pod to restart
kubectl rollout status deployment/immich-server -n immich

# Verify mounts
kubectl exec -n immich deployment/immich-server -c immich-server -- df -h | grep library
```

### Phase 5: Verify and Cleanup
```bash
# Check Immich web UI - verify photos still load
# Check library size on NAS
kubectl exec -n immich deployment/immich-server -c immich-server -- du -sh /usr/src/app/upload/library

# If everything works, delete old library data from SSD
ssh kanokgan@k3s-master
sudo rm -rf /var/lib/rancher/k3s/storage/pvc-5b5c0942-9cac-49c8-9a98-c86f0dfe9b1b_immich_immich-library-pvc/library/

# Verify SSD space freed
df -h /
```

## Rollback Plan
If something goes wrong:
```bash
# Revert server.yaml - remove library-nas volume mount
kubectl rollout undo deployment/immich-server -n immich

# Data is still safe:
# - Original on SSD (until we delete in Phase 5)
# - Copy on NAS
```

## Expected Results
- **Before**: Main SSD 1.4TB used / 457GB free (75%)
- **After**: Main SSD ~450GB used / 1.4TB free (24%)
- **Performance**: Thumbnail/video browsing same speed (on SSD)
- **Trade-off**: Original photo viewing slightly slower (from NAS, but network is fast)

## Files to Modify
- `k8s/immich/server.yaml` - add library-nas volume mount

## Estimated Time
- **Phase 1**: 5 minutes (prep)
- **Phase 2**: 4-6 hours (957GB copy at ~50MB/s)
- **Phase 3-4**: 5 minutes (config + deploy)
- **Phase 5**: 10 minutes (verify + cleanup)
- **Total**: 5-7 hours (mostly waiting for rsync)

## Notes
- Can run rsync in background with `screen` or `tmux`
- No Immich downtime until Phase 4 (pod restart)
- Data is duplicated during migration (safe)
- Network bandwidth: 192.168.0.243 share should handle 50-100MB/s

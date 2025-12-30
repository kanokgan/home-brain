# Jellyfin Media Server Deployment

| Component | Version/Details |
|-----------|----------------|
| Application | Jellyfin latest |
| Deployment | Manual kubectl apply |
| GPU | NVIDIA hardware transcoding (NVENC/NVDEC) |
| Media Source | NAS NFS mount at /Media (read-only) |
| Access | Tailscale HTTPS |
| Storage | Config/cache on local SSD |

## Overview

Jellyfin is deployed on k3s-master with:
- **GPU hardware transcoding**: NVIDIA NVENC/NVDEC with GTX 1650 (10x faster than CPU)
- **GPU time-slicing**: 3 GPU units allocated (Immich ML uses 1 unit)
- **NFS media mount**: Read-only access to NAS at 192.168.0.243:/volume1/Media
- **NVIDIA runtime**: Required for GPU transcoding support
- **Tailscale access**: Private HTTPS access via Tailscale network
- **Local SSD storage**: Config and cache on fast local storage

## Prerequisites

1. **NAS NFS Export**
   ```bash
   # Verify NFS export accessible from k3s-master
   showmount -e 192.168.0.243
   # Should show: /volume1/Media
   
   # Ensure NFS permissions allow k3s-master (192.168.0.206) or entire subnet
   # Synology: Control Panel → Shared Folder → Media → Edit → NFS Permissions
   ``` with Time-Slicing**
   ```bash
   # Verify NVIDIA device plugin is running
   kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset
   
   # Check GPU time-slicing is enabled (should show 4 allocatable GPUs)
   kubectl get node k3s-master -o json | jq '.status.allocatable."nvidia.com/gpu"'
   # Should output: "4"
   # Should already be installed for Immich
   kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset
   ```

3. **Tailscale Auth Key**
   ```bash
   # Use existing reusable auth key or generate new one
   # From Tailscale admin console: Settings > Keys > Generate auth key
   # - Reusable: Yes
   # - Ephemeral: No
   # - Expiration: 90 days
   ```

4. **Local SSD Directories**
   ```bash
   ssh k3s-master
   sudo mkdir -p /mnt/ssd/jellyfin/{config,cache}
   sudo chown -R 1000:1000 /mnt/ssd/jellyfin
   ```

## Deployment Steps

1. **Create Namespace**
   ```bash
   kubectl apply -f k8s/jellyfin/namespace.yaml
   ```

2. **Create Tailscale Secret**
   ```bash
   kubectl create secret generic tailscale-auth -n jellyfin \
     --from-literal=TS_AUTHKEY=tskey-auth-xxx
   ```

3. **Apply Manifests**
   ```bash
   kubectl apply -f k8s/jellyfin/rbac.yaml
   kubectl apply -f k8s/jellyfin/tailscale-config.yaml
   kubectl apply -f k8s/jellyfin/service.yaml
   kubectl apply -f k8s/jellyfin/deployment.yaml
   ```

4. **Verify Deployment**
   ```bash
   # Check pod status
   kubectl get pods -n jellyfin
   
   # Check logs
   kubectl logs -n jellyfin deployment/jellyfin -c jellyfin
   kubectl logs -n jellyfin deployment/jellyfin -c tailscale
   
   # Verify GPU allocation
   kubectl describe pod -n jellyfin -l app=jellyfin | grep -A 5 "Limits"
   ```

5. **Access Jellyfin**
   - URL: https://jellyfin.dove-komodo.ts.net
   - First-time setup wizard will guide through initial configuration

## Initial Configuration

After accessing Jellyfin:

1. **Setup Wizard**
   - Create admin account
   - Skip library setup (do manually)

2. **Hardware Transcoding**
   - Dashboard > Playback > Transcoding
   - Hardware acceleration: NVIDIA NVENC
   - Enable hardware decoding for all formats
   - Enable hardware encoding: H264, HEVC

3. **Add Media Libraries**
   - Dashboard > Libraries > Add Media Library
   - Content type: Movies/TV Shows/Music
   - Folders: Browse to /media/[subfolder]
   - Library options: Enable metadata downloaders

4. **Network Settings**
Current NAS structure at /volume1/Media:
```
/volume1/Media/
  ├── Movies/          # Movie collection
  ├── Series/          # TV Shows
  ├── Animes/          # Anime series
  ├── Kids/            # Kids content
  ├── Live/            # Live content
  ├── MV/              # Music videos
  └── Downloads/       # Download staging
```

Access inside Jellyfin pod: `/media/Movies`, `/media/Series`, etc.   │   │   ├── S01E01.mkv
  │   │   │   └── S01E02.mkv
  └── Music/
      ├── Artist/
      │   └── Album/
      │       └── Track.flac
```

## Performance Notes
Time-Slicing**: 4 virtual GPU units total
  - Jellyfin: 3 units (priority for streaming)
  - Immich ML: 1 unit (background processing)
  - Both can run simultaneously without conflict
- **Transcoding Performance** (GTX 1650): 
  - **10x faster** than CPU transcoding
  - CPU usage: ~5% (vs 89-92% without GPU)
  - Temperature: 61°C GPU (vs 85-97°C CPU)
  - 4K HEVC → 1080p H264: Real-time, multiple concurrent streams
- **Direct Play**: No transcoding when client supports native format
- **NFS Performance**: Read-only NFS sufficient for streaming (transcoding writes to local SSD cache
- **NFS Performance**: Read-only NFS sufficient for streaming (no transcoding writes to NFS)

## Maintenance

### Update Jellyfin

```bash
kubectl set image deployment/jellyfin -n jellyfin jellyfin=jellyfin/jellyfin:latest
kubectl rollout restart deployment/jellyfin -n jellyfin
```

### Refresh Tailscale Auth Key

```bash
kubectl delete secret tailscale-auth -n jellyfin
kubectl create secret generic tailscale-auth -n jellyfin --from-literal=TS_AUTHKEY=tskey-auth-xxx
kubectl rollout restart deployment/jellyfin -n jellyfin
```

### Check Transcoding Activity

```bash
# Via web UI: Dashboard > Activity
# Shows active streams and transcoding status

# Via logs
kubectl logs -n jellyfin deployment/jellyfin -c jellyfin --tail=100 | grep -i transcode
```

### Backup Configuration

```bash
# Config stored on k3s-master:/mnt/ssd/jellyfin/config
ssh k3s-master
sudo tar -czf jellyfin-config-backup-$(date +%Y%m%d).tar.gz /mnt/ssd/jellyfin/config
```

## Troubleshooting

### GPU Not time-slicing allocation
kubectl get node k3s-master -o json | jq '.status.allocatable."nvidia.com/gpu"'

# Check what's using GPU units
kubectl describe node k3s-master | grep -A 15 "Allocated resources:"

# Verify NVIDIA runtime in pod
kubectl exec -n jellyfin deployment/jellyfin -c jellyfin -- nvidia-smi -L
```bash or Uses CPU

**Issue**: Video hangs or CPU usage is high (80%+) during playback

**Solution**: Verify NVIDIA runtime and hardware acceleration settings

```bash
# Check if NVIDIA runtime is enabled (must show runtimeClassName: nvidia)
kubectl get pod -n jellyfin -o yaml | grep runtimeClassName

# Verify NVIDIA devices are accessible
kubectl exec -n jellyfin deployment/jellyfin -c jellyfin -- sh -c 'ls -la /dev/nvidia*'

# Test nvidia-smi works inside container
kubectl exec -n jellyfin deployment/jellyfin -c jellyfin -- nvidia-smi -L

# Check transcoding logs for errors
kubectl logs -n jellyfin deployment/jellyfin -c jellyfin --tail=50 | grep -i -E "(transcode|nvenc|error)"
```
43

# Verify NFS export from k3s-master
ssh k3s-master
showmount -e 192.168.0.243

# Test mount manually
sudo mkdir -p /mnt/test
sudo mount -t nfs 192.168.0.243:/volume1/Media /mnt/test
ls /mnt/test
sudo umount /mnt/test
```

**Common Issues**:
- NAS IP changed: Update deployment.yaml with correct IP
- NFS permissions: Ensure k3s-master IP (192.168.0.206) is allowed in Synology NFS permissions
- NFS not exported: Enable NFS for Media shared folder in Synologyellyfin Settings Required**:
- Dashboard → Playback → Transcoding
- Hardware acceleration: **NVIDIA NVENC** (not "None")
- Enable hardware decoding for: ALL formats
- Enable hardware encoding: ✅ck Jellyfin logs for codec support:
```bash
kubectl logs -n jellyfin deployment/jellyfin -c jellyfin | grep -i nvenc
```

Verify GPU permissions in pod:
```bash
kubectl exec -n jellyfin deployment/jellyfin -c jellyfin -- ls -la /dev/nvidia*
```

### Media Not Accessible

```bash
# Verify NFS mount inside pod
kubectl exec -n jellyfin deployment/jellyfin -c jellyfin -- ls -la /media

# Check NFS server accessibility
kubectl exec -n jellyfin deployment/jellyfin -c jellyfin -- ping -c 3 192.168.0.200
```

### Tailscale Connection Issues

```bash
kubectl logs -n jellyfin deployment/jellyfin -c tailscale
# Look for auth key expiration or network errors
```

## Resource Limits

Current allocation:
- **GPU**: 1 full GPU (shared with Immich via different engines)
- **Memory**: 2Gi minimum (increase if running out during transcoding)
- **CPU**: 1 core minimum (GPU does heavy lifting)

Adjust in deployment.yaml if needed:
```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
    memory: "4Gi"  # Increase for 4K transcoding
  requests:
    memory: "2Gi"
    cpu: "1000m"
```

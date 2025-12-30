# Runbook RB-003: Immich Deployment on K3s

| Field | Value |
|-------|-------|
| Status | Active |
| Version | v2.4.1 (release tag) |
| Updated | 2025-12-30 |
| Cluster | K3s v1.33.6 single-node |
| Deployment | Manual kubectl apply |

## Overview

This runbook covers deploying Immich photo management system on K3s with:
- GPU-accelerated machine learning (NVIDIA GTX 1650)
- Tailscale remote access (immich.dove-komodo.ts.net)
- Local NVMe storage + NAS external libraries
- Production data migration from Docker

## Prerequisites

**Hardware:**
- K3s cluster running (see RB-001)
- NVIDIA GPU with drivers installed
- NVIDIA Container Toolkit configured
- NAS with SMB shares mounted

**Tailscale:**
- Auth key from https://login.tailscale.com/admin/settings/keys
  - Enable "Reusable" and "Ephemeral"
  - Copy the `tskey-auth-...` key

**Storage:**
- Local NVMe for hot data (thumbnails, processed images)
- NAS SMB shares for external libraries

## Step 1: Install NVIDIA Support

### Install NVIDIA Container Toolkit

SSH to k3s-master:

```bash
# Add NVIDIA Container Toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Configure containerd for K3s
sudo nvidia-ctk runtime configure --runtime=containerd --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml

# Restart K3s
sudo systemctl restart k3s
```

### Create NVIDIA Runtime Class

```bash
cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
```

### Deploy NVIDIA Device Plugin

```bash
kubectl apply -f k8s/nvidia-device-plugin.yaml
```

Verify GPU is available:

```bash
kubectl describe node k3s-master | grep nvidia.com/gpu
# Should show: nvidia.com/gpu: 1
```

## Step 2: Mount NAS Shares

On k3s-master, configure SMB mounts in `/etc/fstab`:

```bash
# Create mount points
sudo mkdir -p /mnt/{CameraUploads,JongdeeDrive,PorDrive,PoonDrive,ChurinDrive,OrawanDrive,IPCamera,KanokganDrive,Nrop}

# Add to /etc/fstab (replace NAS_IP and credentials)
//100.77.209.53/CameraUploads /mnt/CameraUploads cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev 0 0
//100.77.209.53/JongdeeDrive /mnt/JongdeeDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev 0 0
# ... (repeat for all shares)

# Mount all
sudo mount -a
```

## Step 3: Deploy Immich

### Configure Secrets

Update secrets with actual values:

```bash
# Edit database and JWT secrets
nano k8s/immich/secrets.yaml

# Update Tailscale auth key
nano k8s/immich/tailscale-secret.yaml
```

### Apply Manifests

```bash
# Namespace with relaxed pod security for hostPath volumes
kubectl apply -f k8s/immich/namespace.yaml

# RBAC for Tailscale sidecar
kubectl apply -f k8s/immich/rbac.yaml

# Secrets and config
kubectl apply -f k8s/immich/secrets.yaml
kubectl apply -f k8s/immich/tailscale-secret.yaml
kubectl apply -f k8s/immich/tailscale-config.yaml
kubectl apply -f k8s/immich/configmap.yaml

# Storage
kubectl apply -f k8s/immich/storage.yaml

# Database and cache
kubectl apply -f k8s/immich/postgres.yaml
kubectl apply -f k8s/immich/redis.yaml

# Machine learning (GPU-accelerated)
kubectl apply -f k8s/immich/machine-learning.yaml

# Server with Tailscale sidecar
kubectl apply -f k8s/immich/server.yaml

# Ingress
kubectl apply -f k8s/immich/ingress.yaml
```

### Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n immich

# Expected output:
# NAME                                       READY   STATUS    RESTARTS   AGE
# immich-server-66b887c98c-xjqbm            2/2     Running   0          5m
# immich-machine-learning-7d4496dbcd-mgmvn  1/1     Running   0          5m
# immich-postgres-7dbc668f7d-gwlgh          1/1     Running   0          5m
# immich-redis-6bf5fd6fd6-m7d2g             1/1     Running   0          5m

# Check Tailscale connection
kubectl logs -n immich -l app=immich-server -c tailscale | tail -5
# Should show: "Startup complete"
```

## Step 4: Access Immich

### Local Access (LAN)

Add to `/etc/hosts` on your Mac:

```
192.168.0.206  immich.home.local
```

Access at: http://immich.home.local

### Remote Access (Tailscale)

Access from any device on your tailnet: https://immich.dove-komodo.ts.net

**First Time Setup:**
1. Create admin account
2. Configure external libraries at `/CameraUploads`, `/JongdeeDrive`, etc.
3. Run initial scan

## Step 5: Data Migration (Optional)

If migrating from existing Immich installation:

### Backup Existing Data

On old server:

```bash
# Backup database
docker exec -t immich_postgres pg_dumpall -c -U postgres > immich_backup.sql

# Backup upload directory
tar -czf immich_upload.tar.gz /path/to/upload
```

### Restore to K3s

```bash
# Copy files to k3s-master
scp immich_backup.sql kanokgan@100.81.236.27:/tmp/
scp immich_upload.tar.gz kanokgan@100.81.236.27:/tmp/

# Restore database
kubectl exec -i -n immich deployment/immich-postgres -- psql -U immich < /tmp/immich_backup.sql

# Extract files to PVC
kubectl exec -n immich deployment/immich-server -- mkdir -p /usr/src/app/upload
# Copy data to PVC storage location on node
sudo tar -xzf /tmp/immich_upload.tar.gz -C /var/lib/rancher/k3s/storage/<pvc-id>/
sudo chown -R 999:999 /var/lib/rancher/k3s/storage/<pvc-id>/

# Restart server
kubectl rollout restart deployment/immich-server -n immich
```

## Monitoring

### Check GPU Usage

```bash
ssh kanokgan@100.81.236.27 nvidia-smi

# During ML tasks, should show 70-80% GPU utilization
```

### Check Logs

```bash
# Server logs
kubectl logs -n immich -l app=immich-server -c immich-server -f

# ML logs
kubectl logs -n immich -l app=immich-machine-learning -f

# Tailscale logs
kubectl logs -n immich -l app=immich-server -c tailscale -f
```

### Check External Libraries

```bash
kubectl exec -n immich deployment/immich-server -- ls -la /CameraUploads
kubectl exec -n immich deployment/immich-server -- ls -la /JongdeeDrive
```

## Troubleshooting

### GPU Not Working

```bash
# Check if device plugin is running
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check if GPU is allocatable
kubectl describe node k3s-master | grep nvidia.com/gpu

# Check ML pod can see GPU
kubectl logs -n immich -l app=immich-machine-learning | grep CUDA
```

### Tailscale Not Connecting

```bash
# Check sidecar logs
kubectl logs -n immich -l app=immich-server -c tailscale

# Verify auth key is valid
kubectl get secret -n immich tailscale-auth -o yaml

# Check RBAC permissions
kubectl get role,rolebinding -n immich | grep tailscale
```

### External Libraries Not Visible

```bash
# Check mounts on node
ssh kanokgan@100.81.236.27 "mount | grep /mnt"

# Check pod can see mounts
kubectl exec -n immich deployment/immich-server -- ls /CameraUploads

# Verify ownership
ssh kanokgan@100.81.236.27 "ls -la /mnt/CameraUploads | head"
# Should show uid=999, gid=999
```

### Pod Security Errors

If you see `violates PodSecurity "baseline:latest": hostPath volumes`:

```bash
# Verify namespace has privileged pod security
kubectl get namespace immich -o yaml | grep pod-security
# Should show: pod-security.kubernetes.io/enforce: privileged
```

## Performance Notes

- GPU acceleration provides 10-20x faster face recognition vs CPU
- Local NVMe storage significantly faster than NAS for thumbnails
- External libraries on NAS via direct LAN connection faster than Tailscale routing
- Timeline scrolling and UI responsiveness much improved vs Docker on MacMini M2

## Maintenance

### Update Immich

```bash
# Pull latest release tag
kubectl set image deployment/immich-server -n immich immich-server=ghcr.io/immich-app/immich-server:release
kubectl set image deployment/immich-machine-learning -n immich immich-machine-learning=ghcr.io/immich-app/immich-machine-learning:release-cuda

# Restart
kubectl rollout restart deployment/immich-server -n immich
kubectl rollout restart deployment/immich-machine-learning -n immich
```

**Note**: Deployments use simple restart strategy without health checks. Ensure no active operations (library scans, face recognition) before updating.

### Refresh Tailscale Auth Key

If Tailscale sidecar fails with auth errors, update the secret:

```bash
# Generate new auth key from Tailscale admin console (reusable, 90-day expiry)
kubectl delete secret tailscale-auth -n immich
kubectl create secret generic tailscale-auth -n immich --from-literal=TS_AUTHKEY=tskey-auth-xxx
kubectl rollout restart deployment/immich-server -n immich
```

### Backup Database

```bash
kubectl exec -n immich deployment/immich-postgres -- pg_dumpall -c -U postgres > immich_backup_$(date +%Y%m%d).sql
```

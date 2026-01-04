# Runbook RB-001: K3s Cluster Infrastructure

| Field | Value |
|-------|-------|
| Status | Active |
| Version | k3s-master: v1.33.6+k3s1, k3s-worker: v1.34.3+k3s1 |
| Updated | 2026-01-04 |
| Architecture | Dual-node: Control plane + worker |
| Hardware | Lenovo X1 Extreme Gen2 + Mac Mini M2 |

## Overview

Home-brain runs on a dual-node K3s cluster with workload specialization:
- **k3s-master:** Control plane + GPU workloads (Immich, Jellyfin)
- **k3s-worker:** API services + future LLM inference (ARM64)

**Networking:**
- **k3s-master:** Ethernet 192.168.0.206 (node-ip, Cloudflare Tunnel), WiFi 192.168.0.189 (failover), Tailscale 100.81.236.27
- **k3s-worker:** OrbStack VM networking via Mac Mini host, Tailscale mesh

**Note:** Cloudflare Tunnel requires Ethernet on k3s-master due to K3s hardcoded `node-ip` and `flannel-iface` bindings.

## Current Infrastructure

### Node: k3s-master (Control Plane)
- **Hostname:** k3s-master
- **OS:** Ubuntu 24.04.3 LTS (Bare Metal)
- **Kernel:** 6.8.0-90-generic
- **CPU:** 12 cores (Intel Core i7-9750H, x86_64)
- **RAM:** 32GB
- **GPU:** NVIDIA GeForce GTX 1650 Mobile (4GB VRAM)
- **K3s Version:** v1.33.6+k3s1
- **Role:** Control plane + GPU-intensive workloads
- **Storage:** 
  - Local NVMe SSD for system + K3s storage
  - NAS: Synology DS923+ (192.168.0.243) via CIFS/SMB

### Node: k3s-worker
- **Hostname:** k3s-worker
- **OS:** Ubuntu 24.04 (OrbStack VM on macOS)
- **Host:** Mac Mini M2 (2023)
- **CPU:** 4 cores (Apple Silicon M2, ARM64)
- **RAM:** 8GB
- **K3s Version:** v1.34.3+k3s1
- **Role:** Worker node for API services and LLM workloads
- **Container Runtime:** OrbStack (lightweight alternative to Docker Desktop)
- **Node Labels:**
  - `workload-type=api-llm`
  - `kubernetes.io/arch=arm64`

### Network Configuration

#### k3s-master Network

##### Ethernet (Primary)
- **Interface:** enp0s31f6
- **IP:** 192.168.0.206
- **Usage:** K3s cluster traffic, Cloudflare Tunnel

##### WiFi (Backup)
- **Interface:** wlp82s0
- **IP:** 192.168.0.189
- **Usage:** Automatic failover (Tailscale only)

##### Tailscale (Remote Access)
- **Interface:** tailscale0
- **IP:** 100.81.236.27
- **Usage:** Remote kubectl access, service access

#### k3s-worker Network

##### OrbStack VM Networking
- **Type:** NAT through Mac Mini host
- **Interface:** eth0
- **IP:** Dynamic (managed by OrbStack)
- **Usage:** Kubernetes pod network, inter-node communication

##### Tailscale (Remote Access)
- **Interface:** tailscale0
- **IP:** Dynamic (100.x.x.x range)
- **Usage:** Remote access, service mesh

### K3s Configuration

#### k3s-master Configuration

**File:** `/etc/rancher/k3s/config.yaml`

```yaml
node-ip: 192.168.0.206           # Hardcoded to Ethernet
flannel-iface: enp0s31f6         # Hardcoded to Ethernet
advertise-address: 100.81.236.27 # Tailscale for remote access
tls-san:
  - 192.168.0.206
  - 100.81.236.27
disable:
  - traefik
write-kubeconfig-mode: "0644"
```

#### k3s-worker Configuration

**Installation command on OrbStack Ubuntu VM:**

```bash
# Get K3s token from master
K3S_TOKEN=$(ssh k3s-master "sudo cat /var/lib/rancher/k3s/server/node-token")
K3S_URL="https://100.81.236.27:6443"  # Master's Tailscale IP

# Install k3s agent
curl -sfL https://get.k3s.io | K3S_URL="${K3S_URL}" K3S_TOKEN="${K3S_TOKEN}" sh -

# Apply node labels
kubectl label node k3s-worker workload-type=api-llm
kubectl label node k3s-worker kubernetes.io/arch=arm64
```

### Storage Configuration

#### NAS CIFS Mounts

**File:** `/etc/fstab` (on k3s-master)

```bash
# Optimized CIFS mounts for Immich external libraries
//192.168.0.243/CameraUploads /mnt/CameraUploads cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/JongdeeDrive /mnt/JongdeeDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/PorDrive /mnt/PorDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/PoonDrive /mnt/PoonDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/ChurinDrive /mnt/ChurinDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/OrawanDrive /mnt/OrawanDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/IPCamera /mnt/IPCamera cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/KanokganDrive /mnt/KanokganDrive cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
//192.168.0.243/Nrop /mnt/Nrop cifs credentials=/root/.smbcredentials,uid=999,gid=999,_netdev,cache=loose,actimeo=30,rsize=130048,wsize=130048,vers=3.1.1 0 0
```

**CIFS Options Explained:**
- `cache=loose`: Aggressive client-side caching for read performance
- `actimeo=30`: Cache file attributes for 30 seconds
- `rsize=130048, wsize=130048`: 128KB read/write buffer (optimal for gigabit)
- `vers=3.1.1`: Force SMB 3.1.1 (fastest modern protocol)
- `_netdev`: Wait for network before mounting

## Installation (Existing Node)

This runbook documents the current state. For fresh installation on similar hardware:

### Prerequisites

```bash
# Install required packages
sudo apt update
sudo apt install -y cifs-utils nfs-common curl

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=k3s-master
```

### Install K3s

```bash
# Create config directory
sudo mkdir -p /etc/rancher/k3s

# Get local IP and Tailscale IP
LOCAL_IP=$(ip -4 addr show enp0s31f6 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
TS_IP=$(tailscale ip -4)

# Create K3s config
sudo tee /etc/rancher/k3s/config.yaml > /dev/null <<EOF
node-ip: ${LOCAL_IP}
flannel-iface: enp0s31f6
advertise-address: ${TS_IP}
tls-san:
  - ${LOCAL_IP}
  - ${TS_IP}
disable:
  - traefik
write-kubeconfig-mode: "0644"
EOF

# Install K3s
curl -sfL https://get.k3s.io | sh -

# Verify installation
sudo kubectl get nodes
```

### Configure kubectl (From Remote Machine)

```bash
# Copy kubeconfig from k3s-master
scp k3s-master:/etc/rancher/k3s/k3s.yaml ~/.kube/config-homebrain

# Update server address to Tailscale IP
TS_IP=100.81.236.27  # Replace with actual Tailscale IP
sed -i "s|127.0.0.1|${TS_IP}|g" ~/.kube/config-homebrain

# Use the config
export KUBECONFIG=~/.kube/config-homebrain
kubectl get nodes
```

## Verification

### Check Node Status
```bash
kubectl get nodes -o wide
# Should show:
# - k3s-master: Ready, v1.33.6+k3s1 (x86_64)
# - k3s-worker: Ready, v1.34.3+k3s1 (arm64)

kubectl describe node k3s-master | grep -E "Addresses|nvidia.com/gpu"
kubectl describe node k3s-worker | grep -E "Addresses|Labels"
```

### Verify Node Labels
```bash
kubectl get nodes --show-labels | grep -E "workload-type|kubernetes.io/arch"
# k3s-worker should have: workload-type=api-llm, kubernetes.io/arch=arm64
```

### Check Deployed Workloads
```bash
# GPU workloads on k3s-master
kubectl get pods -n immich -o wide
kubectl get pods -n jellyfin -o wide

# API workloads on k3s-worker
kubectl get pods -n homebrain -o wide
# homebrain-api pod should be scheduled on k3s-worker
```

### Check CIFS Mounts
```bash
ssh k3s-master "mount | grep cifs"
# Should show all 9 CIFS mounts
```

### Check GPU
```bash
ssh k3s-master "nvidia-smi"
kubectl get nodes -o json | jq '.items[0].status.allocatable."nvidia.com/gpu"'
# Should show "4" (time-slicing enabled)
```

## Troubleshooting

### Metrics Server Not Working

**Symptom:** `kubectl top nodes` fails

**Solution:** Ensure kubelet listens on all interfaces:
```bash
# Check /etc/rancher/k3s/config.yaml - should NOT have bind-address
sudo systemctl restart k3s
```

### Network Failover (Ethernet → WiFi)

**Known Limitation:** Cloudflare Tunnel requires Ethernet.

**During Ethernet failure:**
- ✅ Tailscale access works
- ❌ Cloudflare Tunnel down

### K3s Won't Shut Down

**Cause:** Loki blocking filesystem

**Solution:**
```bash
kubectl scale statefulset loki -n monitoring --replicas=0
sudo systemctl stop k3s
```

## Persistent Storage Configuration

### Storage Classes

**local-path (default):** Single-node local storage
- Path: `/var/lib/rancher/k3s/storage/`
- AccessMode: ReadWriteOnce

**External:** NAS CIFS mounts
- Server: 192.168.0.243
- Protocol: SMB 3.1.1

### Immich Storage Layout

| PVC | Size | Purpose | StorageClass |
|-----|------|---------|--------------|
| immich-library-pvc | 1Ti | User uploads, thumbnails | local-path |
| immich-upload-pvc | 1Ti | Upload staging | local-path |
| immich-ml-cache-pvc | 20Gi | ML models (CLIP, face detection) | local-path |
| immich-redis-pvc | 5Gi | Job queues (AOF persistence) | local-path |

**External Libraries:** Mounted via CIFS from NAS (read-only hostPath)

### Redis Configuration

Immich uses Redis with AOF (Append-Only File) persistence:
- **fsync:** Every second (`--appendfsync everysec`)
- **Data durability:** 1 second max data loss on crash
- **Purpose:** Preserves job queues (thumbnail generation, face recognition, smart search)

```yaml
command:
  - redis-server
  - --appendonly
  - "yes"
  - --appendfsync
  - everysec
```

### ML Cache Persistence

Machine Learning models persist across restarts:
- **CLIP models:** ViT-B-32 (visual embeddings for smart search)
- **Face detection:** RetinaFace, ArcFace
- **Benefits:** Eliminates 19-second model download on pod restart
- **Cache invalidation:** Manual - delete PVC to re-download models

**Check cache usage:**
```bash
kubectl exec -n immich -it $(kubectl get pod -n immich -l app=immich-machine-learning -o name) -- du -sh /cache
```

## See Also
- [GPU Configuration](03-gpu-configuration.md)
- [Cloudflare Tunnel](02-cloudflare-tunnel.md)

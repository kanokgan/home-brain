# GPU Configuration for k3s

## Overview
K3s cluster uses NVIDIA GTX 1650 Mobile with time-slicing to enable GPU sharing across multiple workloads.

**⚠️ CRITICAL:** This guide documents the ONLY method that works with k3s. Do not use `nvidia-ctk` or other standard containerd configuration methods as they will break k3s CNI and other critical features.

## Hardware Specifications

**Hardware:** NVIDIA GeForce GTX 1650 Mobile (4GB VRAM)  
**Host:** k3s-master (Lenovo X1 Extreme Gen2)  
**Driver:** 535.288.01  
**CUDA Version:** 12.2  
**NVIDIA Container Toolkit:** v1.18.1-1  
**Time-Slicing:** 4 virtual GPU slices from 1 physical GPU

### Current GPU Allocation

| Service | GPU Slices | Purpose |
|---------|-----------|---------|
| Immich Server | 1 | Video transcoding |
| Immich ML | 1 | Face recognition, smart search, CLIP embeddings |
| Available | 2 | Reserved for future workloads |

**Total:** 2/4 slices allocated

## Verification Commands

### Check GPU hardware
```bash
lspci | grep -i nvidia
nvidia-smi
```

### Check device plugin
```bash
kubectl get pods -n kube-system | grep nvidia
kubectl get nodes -o json | grep -A5 "nvidia.com/gpu"
```

### Check GPU allocation
```bash
kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,GPU:.spec.containers[*].resources.limits.nvidia\.com/gpu"
```

### Monitor GPU usage
```bash
watch -n 1 nvidia-smi
```

## Installation Steps

### 1. Install NVIDIA Drivers (on k3s-master)

```bash
# Check if GPU is detected
lspci | grep -i nvidia

# Install NVIDIA driver
sudo apt update
sudo apt install nvidia-driver-535 nvidia-utils-535

# Reboot required
sudo reboot

# Verify installation
nvidia-smi
# Should show: Driver Version: 535.288.01, CUDA Version: 12.2
```

### 2. Install NVIDIA Container Toolkit (on k3s-master)

```bash
# Add NVIDIA package repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install toolkit
sudo apt update
sudo apt install nvidia-container-toolkit

# Verify
nvidia-ctk --version
# Should show: NVIDIA Container Toolkit CLI version 1.18.1
```

### 3. Configure k3s Containerd (CRITICAL STEP)

**⚠️ WARNING:** Do NOT run `nvidia-ctk runtime configure` on k3s! It will break your cluster by overwriting k3s's containerd config.

**The ONLY way that works with k3s:**

Create `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` on k3s-master:

```bash
sudo tee /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl > /dev/null << 'EOF'
# Extend k3s base config (preserves CNI, storage, and k3s defaults)
{{ template "base" . }}

# Add NVIDIA runtime configuration
[plugins."io.containerd.cri.v1.runtime".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
EOF
```

**Key Points:**
- The `{{ template "base" . }}` line is CRITICAL - it includes all k3s defaults
- This extends k3s config rather than replacing it
- Without this, CNI and other k3s features will break
- File MUST be at `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` (not `/etc/containerd/`)

Restart k3s to apply:

```bash
sudo systemctl restart k3s
```

### 4. Deploy NVIDIA Device Plugin

Apply the time-slicing configuration:

```bash
kubectl apply -f k8s/nvidia-time-slicing-config.yaml
```

Deploy the device plugin:

```bash
kubectl apply -f k8s/nvidia-device-plugin.yaml
```

Wait for device plugin to start:

```bash
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
# Should show: 1/1 Running
```

### 5. Verify GPU Detection

Check node shows GPU resources:

```bash
kubectl get nodes -o json | jq '.items[0].status.allocatable | {"nvidia.com/gpu"}'
# Should show: "nvidia.com/gpu": "4"
```

Check device plugin logs:

```bash
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
# Should show: "all devices registered successfully"
```

Test GPU allocation:

```bash
kubectl describe node k3s-master | grep -A10 "Allocated resources"
# Should show nvidia.com/gpu: 0/4 (if no workloads using GPU yet)
```

## Configuration Files

### k3s Containerd Template
**File:** `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` (on k3s-master)

```toml
{{ template "base" . }}

[plugins."io.containerd.cri.v1.runtime".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
```

### Time-Slicing Config
**File:** `k8s/nvidia-time-slicing-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: kube-system
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        replicas: 4  # 1 GPU → 4 virtual slices
```

### Device Plugin
**File:** `k8s/nvidia-device-plugin.yaml`

Uses `nvcr.io/nvidia/k8s-device-plugin:v0.17.0` with:
- Minimal configuration (no volume mounts needed)
- `hostNetwork: true` and `hostPID: true`
- Time-slicing enabled via ConfigMap
- Tolerations for control plane

## Adding GPU to Workloads

Workloads do NOT need `runtimeClassName: nvidia` when using k3s with `default_runtime_name = "nvidia"`.

Simply request GPU resources:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload
spec:
  template:
    spec:
      containers:
      - name: app
        image: your-image
        resources:
          limits:
            nvidia.com/gpu: "1"  # Request 1 GPU slice
          requests:
            nvidia.com/gpu: "1"
```

**Available slices:** 4 total (check with `kubectl describe node k3s-master | grep nvidia.com/gpu`)

## Troubleshooting

### ❌ CRITICAL: What NOT To Do

**NEVER run these commands on k3s:**
```bash
# ❌ WILL BREAK K3S CNI AND NETWORKING
sudo nvidia-ctk runtime configure --runtime=containerd
sudo nvidia-ctk runtime configure --runtime=containerd --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml

# These commands:
# 1. Write to /etc/containerd/conf.d/99-nvidia.toml (k3s doesn't read this path)
# 2. Overwrite k3s containerd config (breaks CNI plugins, storage, and k3s features)
# 3. Require full cluster rebuild to recover
```

**If you accidentally ran nvidia-ctk:**
1. Full k3s reinstall required (uninstall + reinstall)
2. All PVC data will be lost
3. Restore from NAS backups

### Device Plugin Shows "ERROR_LIBRARY_NOT_FOUND"

**Symptoms:**
```
Failed to initialize NVML: could not load NVML library
```

**Cause:** containerd not configured with NVIDIA runtime

**Solution:** Verify `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` exists and contains:
```toml
{{ template "base" . }}

[plugins."io.containerd.cri.v1.runtime".containerd]
  default_runtime_name = "nvidia"
```

Then restart k3s:
```bash
sudo systemctl restart k3s
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
```

### Pod Stuck in Pending with "Insufficient nvidia.com/gpu"

**Cause:** All GPU slices allocated

**Solution:**
```bash
# Check current allocation
kubectl describe node k3s-master | grep -A10 "Allocated resources"

# See which pods are using GPU
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.namespace)/\(.metadata.name)"'

# Scale down a workload to free GPU slices
kubectl scale deployment <name> -n <namespace> --replicas=0
```

### GPU Not Detected by Kubernetes

**Checklist:**
1. Check driver on host:
```bash
nvidia-smi
# Should show GPU and driver version 535.288.01
```

2. Check containerd template exists:
```bash
ls -la /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
# Should exist and contain {{ template "base" . }}
```

3. Check device plugin running:
```bash
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
# Should show: 1/1 Running
```

4. Check device plugin logs:
```bash
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
# Look for "all devices registered successfully"
```

5. Reapply configs if needed:
```bash
kubectl apply -f k8s/nvidia-time-slicing-config.yaml
kubectl apply -f k8s/nvidia-device-plugin.yaml
```

### Volume Mount or Library Path Issues

**Do NOT attempt these solutions:**
- ❌ Mounting `/usr/lib/x86_64-linux-gnu` into containers (causes glibc conflicts)
- ❌ Using CDI (Container Device Interface) - not supported in device plugin v0.17.0
- ❌ Custom volume mounts for NVIDIA libraries
- ❌ Init containers to copy libraries

**The runtime handles library access automatically** when containerd is configured correctly.

## Persistent Storage for GPU Workloads

### Immich ML Cache (20Gi)
Stores downloaded ML models (CLIP, face recognition):
- **PVC:** `immich-ml-cache-pvc`
- **Mount:** `/cache` in immich-machine-learning pod
- **Purpose:** Avoid re-downloading models on restart (saves 19 seconds)

### Redis Persistence (5Gi)
Stores job queues with AOF (Append-Only File):
- **PVC:** `immich-redis-pvc`
- **Mount:** `/data` in immich-redis pod
- **Purpose:** Preserve thumbnail/ML job queues across restarts

## Performance Notes

### GPU vs CPU Performance
- **Face recognition:** 10x faster on GPU (GTX 1650) vs 12-core CPU
- **Video transcoding:** 3-5x faster with NVENC/NVDEC hardware acceleration
- **Smart search (CLIP):** GPU required for real-time embedding generation

### Time-Slicing Behavior
- All 4 slices share 4GB VRAM
- GPU time-sliced round-robin
- Memory contention possible if total usage > 4GB
- Best for mixed CPU/GPU workloads (transcoding + ML)

## Maintenance

### Updating Device Plugin
```bash
# Edit version in k8s/nvidia-device-plugin.yaml
kubectl apply -f k8s/nvidia-device-plugin.yaml
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
```

### Changing Time-Slicing Configuration

Edit `k8s/nvidia-time-slicing-config.yaml`:
```yaml
replicas: 4  # Change to desired number of slices
```

Apply and restart device plugin:
```bash
kubectl apply -f k8s/nvidia-time-slicing-config.yaml
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds

# Wait for device plugin to restart
kubectl wait --for=condition=ready pod -n kube-system -l name=nvidia-device-plugin-ds --timeout=60s

# Verify new allocation
kubectl describe node k3s-master | grep nvidia.com/gpu
```

### Updating NVIDIA Driver (on k3s-master)
```bash
# Check current driver
nvidia-smi

# Update to newer driver (Ubuntu/Debian)
sudo apt update
sudo apt install nvidia-driver-545  # or latest version

# Reboot required
sudo reboot

# Verify after reboot
nvidia-smi
kubectl get nodes -o json | jq '.items[0].status.allocatable | {"nvidia.com/gpu"}'

# Restart device plugin if needed
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
```

## Why This Method Works

### The k3s Containerd Challenge

k3s uses an embedded containerd with its own configuration system:
- **Config location:** `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`
- **Template system:** Uses Go templates to generate final config
- **Base config:** Contains CNI, storage, and k3s-specific settings

### Failed Approaches and Why

1. **nvidia-ctk runtime configure:**
   - Writes to `/etc/containerd/config.toml` (k3s doesn't read this)
   - Or overwrites k3s config without preserving base settings
   - Breaks CNI, requiring full cluster rebuild

2. **Volume mounts for NVIDIA libraries:**
   - Causes glibc version conflicts between host and container
   - Container runtime should provide library access, not volume mounts

3. **CDI (Container Device Interface):**
   - Not supported by device plugin v0.17.0
   - Requires newer versions with different architecture

### The Working Solution

The `config.toml.tmpl` approach:
1. **Extends rather than replaces:** `{{ template "base" . }}` includes all k3s defaults
2. **Sets default runtime:** All containers get NVIDIA runtime automatically
3. **Proper library access:** Runtime provides CUDA/NVML libraries to containers
4. **Preserves k3s features:** CNI, storage, and k3s-specific settings intact

This is the ONLY method that works reliably with k3s.

## Disaster Recovery

If GPU configuration is broken and cluster needs rebuild:

1. **Backup critical data** (automatic CronJob runs daily at 3 AM):
```bash
# Check latest backup
ls -lh /mnt/HomeBrain/backups/pvc-backups/
```

2. **Uninstall k3s:**
```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

3. **Reinstall k3s:**
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.33.6+k3s1 sh -
```

4. **Reconfigure GPU** (follow Installation Steps 3-5)

5. **Restore data from backups** (see disaster recovery scripts)

## Related Documentation
- [Infrastructure Setup](01-infrastructure.md)
- [Immich Deployment](04-immich-deployment.md)
- NVIDIA Device Plugin: https://github.com/NVIDIA/k8s-device-plugin
- CUDA Containers: https://docs.nvidia.com/datacenter/cloud-native/
- k3s Advanced Options: https://docs.k3s.io/advanced

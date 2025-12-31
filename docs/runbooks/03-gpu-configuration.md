# GPU Configuration

## Overview
K3s cluster uses NVIDIA GTX 1650 Mobile with time-slicing to enable GPU sharing across multiple workloads.

## GPU Time-Slicing Configuration

**Hardware:** NVIDIA GeForce GTX 1650 Mobile (4GB VRAM)  
**Driver:** 535.274.02  
**CUDA Version:** 12.2  
**Time-Slicing:** 4 virtual GPU slices

### Current GPU Allocation

| Service | GPU Slices | Purpose |
|---------|-----------|---------|
| Jellyfin | 2 | Video transcoding (HEVC, H264) |
| Immich Server | 1 | Video transcoding |
| Immich ML | 1 | Face recognition, smart search, CLIP embeddings |

**Total:** 4/4 slices allocated

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

## Configuration Files

### Time-Slicing Config
**File:** `k8s/nvidia-time-slicing-config.yaml`

```yaml
replicas: 4  # Divides 1 physical GPU into 4 virtual slices
```

### Device Plugin
**File:** `k8s/nvidia-device-plugin.yaml`

Uses `nvcr.io/nvidia/k8s-device-plugin:v0.14.0` with:
- `runtimeClassName: nvidia`
- MIG disabled
- Time-slicing enabled via ConfigMap

## Adding GPU to New Service

1. **Add runtime class to deployment:**
```yaml
spec:
  template:
    spec:
      runtimeClassName: nvidia
```

2. **Request GPU resources:**
```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
  requests:
    nvidia.com/gpu: "1"
```

3. **Verify available slices:** Max 4 total across all pods

## Troubleshooting

### Pod stuck in Pending with "Insufficient nvidia.com/gpu"

**Cause:** All 4 GPU slices allocated

**Solution:**
```bash
# Check current allocation
kubectl get pods --all-namespaces -o json | grep -B5 "nvidia.com/gpu"

# Reduce GPU request for other services
# Or scale down conflicting deployments
kubectl scale deployment <name> -n <namespace> --replicas=0
```

### "Cannot load libcuda.so.1" error

**Cause:** Container can't access NVIDIA runtime

**Solutions:**
1. Check runtimeClassName:
```bash
kubectl get pod <pod> -n <namespace> -o yaml | grep runtimeClassName
```

2. Verify NVIDIA runtime in K3s:
```bash
grep -A5 nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml
```

3. Restart device plugin:
```bash
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
```

### GPU not detected by K8s

1. **Check driver:**
```bash
nvidia-smi
# Should show GPU and driver version
```

2. **Check device plugin:**
```bash
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
```

3. **Reapply configs:**
```bash
kubectl apply -f k8s/nvidia-time-slicing-config.yaml
kubectl apply -f k8s/nvidia-device-plugin.yaml
```

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

### Changing Time-Slicing
```bash
# Edit replicas in k8s/nvidia-time-slicing-config.yaml
kubectl apply -f k8s/nvidia-time-slicing-config.yaml
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
# Update deployment GPU requests accordingly
```

### Driver Updates (on k3s-master)
```bash
# Check current driver
nvidia-smi

# Update NVIDIA driver (Ubuntu/Debian)
sudo apt update
sudo apt install nvidia-driver-535  # or latest

# Reboot required
sudo reboot

# Verify after reboot
nvidia-smi
kubectl get nodes -o json | grep "nvidia.com/gpu"
```

## Related Documentation
- [Infrastructure Setup](01-infrastructure.md)
- NVIDIA Device Plugin: https://github.com/NVIDIA/k8s-device-plugin
- CUDA Containers: https://docs.nvidia.com/datacenter/cloud-native/

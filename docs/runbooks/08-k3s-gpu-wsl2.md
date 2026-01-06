# RB-008: k3s-gpu Node Setup (WSL2 with RTX 4060)

**Status:** ✅ Complete  
**Node:** k3s-gpu (Gaming PC with Windows + WSL2 Ubuntu 24.04)  
**Purpose:** GPU-accelerated batch workloads (video transcoding)  
**Hardware:** Intel i5-13400 (16 cores), NVIDIA RTX 4060 (8GB VRAM)

## Overview

This runbook documents the setup of a K3s worker node on Windows using WSL2 for GPU-accelerated workloads. The node joins the cluster via Tailscale mesh network and provides dedicated GPU resources for batch processing tasks like video transcoding.

**Key Features:**
- WSL2 Ubuntu 24.04 on Windows (preserves gaming PC functionality)
- RTX 4060 GPU accessible in containers via NVIDIA Container Toolkit
- K3s agent joined via Tailscale (not direct LAN due to WSL2 NAT)
- NFS client for NAS mounts (video transcoding workloads)
- GPU sharing enabled (no resource limits for parallel workers)

## Prerequisites

- Windows 10/11 with WSL2 enabled
- NVIDIA GPU with latest Windows drivers installed
- Tailscale account and auth key
- K3s cluster already running (k3s-master accessible)
- K3s join token from master node

## Step 1: Install WSL2 Ubuntu 24.04

```powershell
# In PowerShell (Administrator)
wsl --install -d Ubuntu-24.04
```

After installation, set Ubuntu as default and configure:

```bash
# Set username/password during first launch
# Update hostname
sudo hostnamectl set-hostname k3s-gpu

# Update /etc/hosts
sudo nano /etc/hosts
# Change 127.0.1.1 line to: 127.0.1.1 k3s-gpu

# Update system
sudo apt update && sudo apt upgrade -y
```

## Step 2: Configure Tailscale

Install Tailscale for secure cluster connectivity:

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Join Tailscale network (replace with your auth key)
sudo tailscale up --authkey=tskey-auth-XXXXX --hostname=k3s-gpu
```

Verify connectivity to k3s-master:

```bash
# Get k3s-master Tailscale IP
ping 100.81.236.27

# Test K3s API connectivity
curl -k https://100.81.236.27:6443
```

## Step 3: Install CUDA Toolkit (WSL2-specific)

NVIDIA drivers are inherited from Windows, but CUDA toolkit is needed:

```bash
# Add NVIDIA CUDA repository (WSL-specific)
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/3bf863cc.pub
sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/ /"

# Install CUDA toolkit
sudo apt update
sudo apt install -y cuda-toolkit-12-6

# Add NVIDIA libraries to PATH
echo 'export PATH=/usr/lib/wsl/lib:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verify nvidia-smi works
/usr/lib/wsl/lib/nvidia-smi
```

**Expected Output:**
```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 565.90                 Driver Version: 565.90         CUDA Version: 12.7     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                  Driver-Model | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 4060     WDDM  |   00000000:01:00.0  On |                  N/A |
|  0%   30C    P8             13W /  115W |     714MiB /   8188MiB |      2%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
```

## Step 4: Install NVIDIA Container Toolkit

Required for GPU access in containers:

```bash
# Add NVIDIA Container Toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit=1.18.1-1
```

## Step 5: Install K3s Agent

Install K3s and join cluster via Tailscale:

```bash
# Install NFS client (required for NAS mounts)
sudo apt install -y nfs-common

# Install K3s agent
# Replace K3S_URL and K3S_TOKEN with your values
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.34.3+k3s1" \
  K3S_URL="https://100.81.236.27:6443" \
  K3S_TOKEN="K10XXXXX::server:XXXXX" \
  sh -s - agent \
  --node-name k3s-gpu

# Wait for service to start
sudo systemctl status k3s-agent
```

## Step 6: Configure containerd for NVIDIA Runtime

K3s uses containerd, which needs NVIDIA runtime configuration:

```bash
# Configure NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=containerd \
  --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml

# Restart K3s agent to apply changes
sudo systemctl restart k3s-agent

# Wait 30 seconds for restart
sleep 30

# Verify node joined cluster (from k3s-master)
kubectl get nodes
```

**Expected Output:**
```
NAME         STATUS   ROLES                  AGE   VERSION
k3s-master   Ready    control-plane,master   30d   v1.33.6+k3s1
k3s-gpu      Ready    <none>                 1m    v1.34.3+k3s1
```

## Step 7: Deploy NVIDIA Device Plugin

The device plugin exposes GPU to Kubernetes:

```bash
# From k3s-master, ensure plugin is deployed
kubectl apply -f k8s/nvidia-device-plugin.yaml

# Wait for plugin pod to run on k3s-gpu
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds -o wide

# Verify GPU is allocatable
kubectl describe node k3s-gpu | grep -A5 "Capacity:"
```

**Expected Output:**
```
Capacity:
  cpu:                16
  ephemeral-storage:  1006G
  memory:             32Gi
  nvidia.com/gpu:     1
  pods:               110
```

## Step 8: Label Node for Workloads

Add labels for workload scheduling:

```bash
kubectl label node k3s-gpu gpu-type=rtx4060
kubectl label node k3s-gpu workload-type=gpu-transcode
```

## Step 9: Verify GPU Access in Containers

Test GPU accessibility:

```bash
# Create test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-gpu
  namespace: default
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  nodeSelector:
    kubernetes.io/hostname: k3s-gpu
  containers:
  - name: cuda
    image: nvidia/cuda:12.6.0-base-ubuntu24.04
    command: ["nvidia-smi"]
EOF

# Check logs
kubectl logs test-gpu

# Cleanup
kubectl delete pod test-gpu
```

If logs show GPU information, setup is successful!

## Troubleshooting

### Issue: nvidia-smi not found

**Symptom:** `bash: nvidia-smi: command not found`

**Solution:** Use full path or add to PATH:
```bash
/usr/lib/wsl/lib/nvidia-smi
# OR
export PATH=/usr/lib/wsl/lib:$PATH
```

### Issue: K3s agent can't reach master LAN IP

**Symptom:** Connection timeout to `https://192.168.0.206:6443`

**Solution:** WSL2 uses NAT, can't directly reach LAN. Use Tailscale IP instead:
```bash
# Use k3s-master Tailscale IP
K3S_URL="https://100.81.236.27:6443"
```

### Issue: NVIDIA device plugin pod fails on k3s-gpu

**Symptom:** Device plugin in `CrashLoopBackOff` on k3s-gpu node

**Solution:** Change discovery strategy from "auto" to "nvml" in ConfigMap:
```yaml
# k8s/nvidia-device-plugin.yaml
data:
  config.yaml: |
    version: v1
    flags:
      deviceDiscoveryStrategy: "nvml"  # Not "auto" for WSL2
```

Then restart plugin:
```bash
kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
```

### Issue: Container can't access GPU libraries

**Symptom:** `libnvidia-encode.so.1: cannot open shared object file`

**Solution:** Mount WSL2 NVIDIA libraries into container:
```yaml
volumeMounts:
- name: nvidia-libs
  mountPath: /usr/local/nvidia/lib64
  readOnly: true
volumes:
- name: nvidia-libs
  hostPath:
    path: /usr/lib/wsl/lib
    type: Directory
env:
- name: LD_LIBRARY_PATH
  value: "/usr/local/nvidia/lib64:/usr/lib/x86_64-linux-gnu"
```

### Issue: Multiple pods can't share GPU

**Symptom:** Pods pending with "Insufficient nvidia.com/gpu"

**Solution:** Remove GPU resource limits to enable sharing:
```yaml
# Remove these lines:
resources:
  limits:
    nvidia.com/gpu: "1"
  requests:
    nvidia.com/gpu: "1"
```

**Note:** GPU sharing is not officially supported by Kubernetes but works for batch workloads that don't fully saturate GPU.

## WSL2-Specific Notes

### NVIDIA Libraries Location
- Windows drivers provide libraries in `/usr/lib/wsl/lib/`
- Standard Linux location `/usr/lib/x86_64-linux-gnu/` may not have all GPU libraries
- Containers need explicit volume mounts to access WSL2 libraries

### Networking Limitations
- WSL2 uses NAT, not bridged networking
- Can't directly access LAN IPs from WSL2
- Flannel CNI double-encapsulation issues when joining via Tailscale
- Solution: Join via Tailscale IP (100.x.x.x), accept Flannel overhead for control plane only

### NFS Mounts
- NFS client must be installed: `sudo apt install nfs-common`
- K3s agent needs restart after installing nfs-common
- NFS mounts work normally from pods once client is installed

### CUDA Compatibility
- Use WSL-specific CUDA repository, not standard Ubuntu repo
- Driver version inherited from Windows
- CUDA version in WSL2 may differ from Windows
- Use `cuda-wsl-ubuntu` packages, not `cuda-ubuntu`

## Maintenance

### Restart K3s Agent
```bash
sudo systemctl restart k3s-agent
```

### View K3s Agent Logs
```bash
sudo journalctl -u k3s-agent -f
```

### Update NVIDIA Drivers
Update Windows NVIDIA drivers (not WSL2). WSL2 will automatically use new driver.

### Backup Configuration
Important files to backup:
- `/etc/systemd/system/k3s-agent.service.env` (join token)
- `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` (NVIDIA runtime config)

## Next Steps

After k3s-gpu setup is complete, you can:
1. Deploy GPU-accelerated workloads: [RB-009: Video Transcoding](09-video-transcoding.md)
2. Monitor GPU utilization from Windows Task Manager
3. Scale parallel workers based on GPU capacity

## References

- [NVIDIA Container Toolkit Documentation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- [K3s Documentation](https://docs.k3s.io/)
- [NVIDIA Device Plugin for Kubernetes](https://github.com/NVIDIA/k8s-device-plugin)
- [WSL2 CUDA Support](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)

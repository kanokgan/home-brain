# Runbook RB-001: K3s Cluster Provisioning

| Field | Value |
|-------|-------|
| Status | Active |
| Version | v1.33.6+k3s1 |
| Updated | 2025-12-08 |

## Prerequisites

Generate Tailscale auth key: https://login.tailscale.com/admin/settings/keys

```bash
export TS_AUTH_KEY="tskey-auth-..."
export MASTER_IP=""  # Will be set in Step 1
export NODE_TOKEN="" # Will be set in Step 1
```

## Step 1: Control Plane (Mac Mini M2)

```bash
# Launch VM with Tailscale
multipass launch --name k3s-master --cpus 2 --memory 4G --disk 20G --cloud-init - <<EOF
package_update: true
package_upgrade: true
runcmd:
  - curl -fsSL https://tailscale.com/install.sh | sh
EOF

# Authenticate and get IP
multipass exec k3s-master -- sudo tailscale up --authkey=${TS_AUTH_KEY}
MASTER_IP=$(multipass exec k3s-master -- tailscale ip -4)
echo "Master IP: $MASTER_IP"

# Install K3s
multipass exec k3s-master -- bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server \
  --node-ip ${MASTER_IP} \
  --node-external-ip ${MASTER_IP} \
  --flannel-iface tailscale0 \
  --disable traefik \
  --write-kubeconfig-mode 644' sh -"

# Get node token
NODE_TOKEN=$(multipass exec k3s-master -- sudo cat /var/lib/rancher/k3s/server/node-token)
echo "Node Token: $NODE_TOKEN"
```

**Manual:** Disable key expiry in Tailscale Admin Console for `k3s-master`.

## Step 2: GPU Worker (Windows WSL2)

Run in PowerShell (Admin):
```powershell
wsl --install -d Ubuntu-22.04
```

Run in WSL2 Ubuntu:
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey ${TS_AUTH_KEY} --hostname=k3s-worker-gpu
WORKER_IP=$(tailscale ip -4)

# Install NFS client
sudo apt-get update && sudo apt-get install -y nfs-common

# Join cluster (use MASTER_IP and NODE_TOKEN from Step 1)
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="${NODE_TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-external-ip=${WORKER_IP} \
    --flannel-iface=tailscale0 \
    --kubelet-arg=eviction-hard=imagefs.available<1% \
    --kubelet-arg=eviction-hard=nodefs.available<1%" sh -
```

**Manual:** Disable key expiry in Tailscale Admin Console for `k3s-worker-gpu`.

## Step 3: Compute Worker (Lenovo X1 Extreme Gen2)

Run on Ubuntu 22.04:
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=k3s-worker-extreme
WORKER_IP=$(tailscale ip -4)

# Install NFS client
sudo apt-get update && sudo apt-get install -y nfs-common

# Join cluster (use MASTER_IP and NODE_TOKEN from Step 1)
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="${NODE_TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-external-ip=${WORKER_IP} \
    --flannel-iface=tailscale0" sh -
```

**Manual:** Disable key expiry in Tailscale Admin Console for `k3s-worker-extreme`.

**Enable GPU support (X1 has GTX 1650 Mobile):**
```bash
# Install NVIDIA driver
sudo apt-get update
sudo apt-get install -y nvidia-driver-535

# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit libnvidia-ml-dev

# Configure containerd
sudo nvidia-ctk runtime configure --runtime=containerd --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml
sudo systemctl restart k3s-agent

# Verify driver
nvidia-smi
```

On your Mac, install GPU Operator:
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=false

# Verify GPU detected
kubectl get node k3s-worker-extreme -o json | jq '.status.capacity."nvidia.com/gpu"'
```

## Step 4: NFS Storage (Synology DS923+)

**Synology DSM Manual Steps:**
1. Control Panel → File Services → Enable NFS (NFSv4.1)
2. Control Panel → Shared Folder → Create `k3s-data`
3. Edit folder → NFS Permissions:
   - Hostname: `*` or `100.64.0.0/10`
   - Privilege: Read/Write
   - Squash: Map all users to admin
   - Enable: Allow non-privileged ports

**Install NFS Provisioner:**
```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm install nfs-storage nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-storage \
  --create-namespace \
  --set nfs.server=192.168.x.x \
  --set nfs.path=/volume1/k3s-data \
  --set storageClass.name=nfs-client
```

## Step 5: Verification

**Configure kubectl access:**
```bash
multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config-homebrain
sed -i '' "s/127.0.0.1/$(multipass exec k3s-master -- tailscale ip -4)/g" ~/.kube/config-homebrain
export KUBECONFIG=~/.kube/config-homebrain
kubectl get nodes -o wide
```

**Test NFS:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs
spec:
  storageClassName: nfs-client
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-nfs
kubectl delete pvc test-nfs
```

## Troubleshooting

**Worker not joining:**
```bash
ping -c 3 $MASTER_IP  # Test connectivity
sudo journalctl -u k3s-agent -f  # Check logs
```

**WSL2 disk capacity error:**
Add to agent install: `--kubelet-arg=eviction-hard=imagefs.available<1% --kubelet-arg=eviction-hard=nodefs.available<1%`

**NFS mount fails:**
```bash
sudo apt-get install -y nfs-common
sudo systemctl restart k3s-agent
```

**Reset node:**
```bash
kubectl delete node <node-name>  # On master
sudo /usr/local/bin/k3s-agent-uninstall.sh  # On worker
```

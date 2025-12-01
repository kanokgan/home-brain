# 🏃 Runbook: Phase 1 - Hybrid Cluster Provisioning

| Metadata | Details |
| :--- | :--- |
| **ID** | RB-001 |
| **Status** | Active - Tested & Working |
| **Maintainer** | @Kanokgan |
| **Last Updated** | 2025-12-01 |
| **Objective** | Provision a K3s Control Plane (Mac/ARM64) and GPU Worker Node (Windows/WSL2) with external NFS Storage. |
| **K3s Version** | v1.33.6+k3s1 |

---

## 🛑 Security Prerequisites (READ FIRST)
Since this repository is **Public**, never paste keys directly into terminal commands that might be logged to history files (`~/.zsh_history` or `~/.bash_history`).

1.  **Tailscale Auth Key:** Generate a Reusable, Ephemeral key from the [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2.  **Define Secrets Locally:** Run this in your terminal before executing commands:
    ```bash
    export TS_AUTH_KEY="tskey-auth-..."  # Your generated key
    ```

---

## 🖥 Step 1: Provision Control Plane (Mac Mini M2)

**Context:** We use Multipass to create a lightweight Ubuntu VM on the Apple Silicon chip. This VM acts as the Kubernetes Master.

### 1.1 Launch VM with Cloud-Init
Creates the VM and automatically installs Tailscale.

```bash
# Execute on Mac Host
multipass launch --name k3s-master \
  --cpus 2 \
  --memory 4G \
  --disk 20G \
  --cloud-init - <<EOF
package_update: true
package_upgrade: true
runcmd:
  - curl -fsSL [https://tailscale.com/install.sh](https://tailscale.com/install.sh) | sh
EOF
```

### 1.2 Authenticate & IP Retrieval

We authenticate the node and retrieve its Tailscale IP to bind K3s correctly.

```bash
# 1. Authenticate (Click the link returned)
multipass exec k3s-master -- sudo tailscale up --authkey=${TS_AUTH_KEY}

# 2. Get the Tailscale IP (Capture this!)
MASTER_IP=$(multipass exec k3s-master -- tailscale ip -4)
echo "Master Node IP is: $MASTER_IP"
```

> **Manual Action:** Go to Tailscale Admin Console -\> Machines -\> `k3s-master` -\> **"Disable Key Expiry"**.

### 1.3 Install K3s (Master Mode)

We bind K3s explicitly to the Tailscale interface (`tailscale0`) to allow remote workers to join.

```bash
# Verify the IP before installation
echo "Installing K3s with Master IP: $MASTER_IP"

multipass exec k3s-master -- bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server \
  --node-ip ${MASTER_IP} \
  --node-external-ip ${MASTER_IP} \
  --flannel-iface tailscale0 \
  --disable traefik \
  --write-kubeconfig-mode 644' sh -"

# Wait for K3s to start
sleep 10

# Verify installation
multipass exec k3s-master -- sudo k3s kubectl get nodes
```

### 1.4 Extract Node Token

Required for the Windows Worker to join.

```bash
# Save securely! Do NOT commit.
NODE_TOKEN=$(multipass exec k3s-master -- sudo cat /var/lib/rancher/k3s/server/node-token)
echo "Node Token: $NODE_TOKEN"
echo "Save this token for worker setup!"
```

-----

## 🎮 Step 2: Provision GPU Worker (Windows 11)

**Context:** We use **WSL2 (Windows Subsystem for Linux)** to run K3s. This allows the node to access the host GPU (RTX 4060) while running in a Linux environment compatible with K3s.

### 2.1 Prepare WSL2

Open **PowerShell (Admin)** on Windows:

```powershell
# 1. Install Ubuntu 22.04
wsl --install -d Ubuntu-22.04

# 2. (Optional) Fix systemd if not enabled
# Inside Ubuntu: echo -e "[boot]\nsystemd=true" | sudo tee /etc/wsl.conf
# Then restart wsl: wsl --shutdown
```

### 2.2 Configure Networking (Inside WSL2)

Open your Ubuntu terminal on Windows. We install a **standalone Tailscale instance** inside WSL2 to ensure direct connectivity to the Master.

```bash
# 1. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# 2. Authenticate
sudo tailscale up --authkey <YOUR_TS_AUTH_KEY> --hostname=k3s-worker-gpu

# 3. Get IP and verify connectivity
WORKER_IP=$(tailscale ip -4)
echo "Worker IP: $WORKER_IP"

# 4. Test connection to master
ping -c 3 $MASTER_IP
```

> **Manual Action:** Go to Tailscale Admin Console -\> Machines -\> `k3s-worker-gpu` -\> **"Disable Key Expiry"**.

### 2.3 Install NFS Client (CRITICAL)

**This step is essential for pods to mount NFS volumes from Synology.**

```bash
sudo apt-get update
sudo apt-get install -y nfs-common

# Verify NFS is available
systemctl status rpc-statd
```

### 2.4 Join Cluster

Run this inside the WSL2 Ubuntu terminal:

```bash
# Variables (Replace with actual values from Step 1)
MASTER_IP="100.x.x.x"      # Your master Tailscale IP from step 1.2
NODE_TOKEN="K10..."        # Your token from step 1.4
WORKER_IP=$(tailscale ip -4)    # Already set from step 2.2

# Install K3s Agent with WSL2-specific settings
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="${NODE_TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-external-ip=${WORKER_IP} \
    --flannel-iface=tailscale0 \
    --kubelet-arg=eviction-hard=imagefs.available<1% \
    --kubelet-arg=eviction-hard=nodefs.available<1%" sh -

# Note: WSL2 cannot report disk capacity correctly to Kubernetes.
# The eviction-hard settings above prevent kubelet crashes.
# DO NOT use --kubelet-arg=image-fs-min-avail - it's unsupported in K3s v1.33+

# Wait for agent to start
sleep 10

# Check status
sudo systemctl status k3s-agent
```

-----

## 🗄 Step 3: Configure Storage (Synology NAS)

**Context:** The Synology DS923+ serves as the persistent storage layer (NFS) for the cluster.

### 3.1 Enable NFS Service

1.  Log into Synology DSM.
2.  Go to **Control Panel** -\> **File Services** -\> **NFS**.
3.  Check **Enable NFS Service**.
4.  Set **Maximum NFS protocol** to `NFSv4.1`.

### 3.2 Create Shared Folder

1.  Go to **Control Panel** -\> **Shared Folder**.
2.  Create a new folder named `k3s-data`.
3.  **Edit** the folder -\> **NFS Permissions** tab -\> **Create**.
      * **Hostname/IP:** `*` (Or your Tailscale Subnet `100.64.0.0/10` for security).
      * **Privilege:** Read/Write.
      * **Squash:** Map all users to admin (Simplifies permission issues in home labs).
      * **Security:** `sys`.
      * **Tick:** Allow connections from non-privileged ports.

### 3.3 Install NFS Provisioner

Deploy the nfs-subdir-external-provisioner to enable dynamic PVC creation:

```bash
# Add Helm repo
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

# Install with Synology settings (replace with your NAS IP)
helm install nfs-storage nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-storage \
  --create-namespace \
  --set nfs.server=192.168.x.x \
  --set nfs.path=/volume1/k3s-data \
  --set storageClass.name=nfs-client

# Verify deployment
kubectl get pods -n nfs-storage
kubectl get storageclass
```

### 3.4 Test NFS Storage

Create a test PVC to verify NFS is working:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs
spec:
  storageClassName: nfs-client
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status (should be Bound)
kubectl get pvc test-nfs

# Cleanup
kubectl delete pvc test-nfs
```

-----

## 🧪 Step 4: Verification & Access

### 4.1 Configure Host Access (Mac Terminal)

Pull the kubeconfig to your host to manage the cluster via VS Code / Lens.

```bash
# 1. Copy config to host
multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config-homebrain

# 2. Replace localhost with Master's Tailscale IP
sed -i '' "s/127.0.0.1/$(multipass exec k3s-master -- tailscale ip -4)/g" ~/.kube/config-homebrain

# 3. Test
export KUBECONFIG=~/.kube/config-homebrain
kubectl get nodes -o wide
```

### 4.2 Success Criteria

✅ Output should look like this:

```text
NAME             STATUS   ROLES                  AGE   VERSION         INTERNAL-IP   OS-IMAGE
k3s-master       Ready    control-plane,master   1d    v1.33.6+k3s1    100.x.x.x     Ubuntu 22.04.5 LTS
<windows-hostname>   Ready    <none>             2h    v1.33.6+k3s1    100.y.y.y     Ubuntu 22.04.5 LTS
```

**Note:** The worker node hostname will be your Windows PC hostname (e.g., `tor-homepc`), not `k3s-worker-gpu`.

### 4.3 Verify Storage

```bash
# Check NFS provisioner is running
kubectl get pods -n nfs-storage

# Expected output:
# NAME                                                        READY   STATUS
# nfs-storage-nfs-subdir-external-provisioner-xxxxx          1/1     Running

# Check storage class
kubectl get storageclass

# Expected output:
# NAME                   PROVISIONER                            RECLAIMPOLICY
# nfs-client (default)   cluster.local/nfs-storage-nfs-sub...   Delete
```

-----

## 🆘 Troubleshooting

### Issue 1: Worker Node Not Joining

**Symptoms:** Windows Worker shows as "NotReady" or doesn't appear in `kubectl get nodes`.

1.  **Firewall:** Ensure Windows Defender isn't blocking the WSL network adapter.
2.  **Tailscale:** Ensure both `k3s-master` and worker can ping each other:
    ```bash
    # On WSL2 (replace with your master IP):
    ping -c 3 $MASTER_IP
    ```
3.  **Check Logs:**
    ```bash
    # Master: 
    multipass exec k3s-master -- sudo journalctl -u k3s -f
    
    # Worker (in WSL2):
    sudo journalctl -u k3s-agent -f
    ```

### Issue 2: Kubelet Crash Loop (InvalidDiskCapacity)

**Symptoms:** `journalctl -u k3s-agent` shows "invalid capacity 0 on image filesystem"

**Root Cause:** WSL2 cannot report disk capacity metrics to Kubernetes.

**Solution:** Use the eviction-hard settings in the installation command (already included in Step 2.4):
```bash
--kubelet-arg=eviction-hard=imagefs.available<1% \
--kubelet-arg=eviction-hard=nodefs.available<1%
```

### Issue 3: Pods Stuck in ContainerCreating (NFS Mount Failed)

**Symptoms:** Pods stuck in `ContainerCreating` with events showing "MountVolume.SetUp failed for volume"

**Root Cause:** `nfs-common` package not installed on worker node.

**Solution:** Install NFS client (Step 2.3):
```bash
sudo apt-get install -y nfs-common
```

Then restart k3s-agent:
```bash
sudo systemctl restart k3s-agent
```

### Issue 4: Old Node Registration

**Symptoms:** Node shows old Tailscale IP or stuck in "NotReady" after IP change.

**Solution:** Delete the old node and re-register:
```bash
# On master:
kubectl delete node <old-node-name>

# On worker (WSL2):
sudo /usr/local/bin/k3s-agent-uninstall.sh
# Then re-run the installation from Step 2.4
```

### Issue 5: systemd Override File Issues

**Symptoms:** k3s-agent fails to start with "unknown flag" errors.

**Root Cause:** Bad systemd override file with unevaluated variables or unsupported flags.

**Solution:** Remove override directory and reinstall:
```bash
sudo rm -rf /etc/systemd/system/k3s-agent.service.d
sudo systemctl daemon-reload
sudo /usr/local/bin/k3s-agent-uninstall.sh
# Then re-run the installation from Step 2.4
```

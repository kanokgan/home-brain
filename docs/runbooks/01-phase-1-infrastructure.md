# 🏃 Runbook: Phase 1 - Hybrid Cluster Provisioning

| Metadata | Details |
| :--- | :--- |
| **ID** | RB-001 |
| **Status** | Active |
| **Maintainer** | @Kanokgan |
| **Last Updated** | 2025-11-27 |
| **Objective** | Provision a K3s Control Plane (Mac/ARM64) and GPU Worker Node (Windows/WSL2) with external NFS Storage. |

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
multipass exec k3s-master -- bash -c "curl -sfL [https://get.k3s.io](https://get.k3s.io) | INSTALL_K3S_EXEC='server \
  --node-ip ${MASTER_IP} \
  --node-external-ip ${MASTER_IP} \
  --flannel-iface tailscale0 \
  --disable traefik \
  --write-kubeconfig-mode 644' sh -"
```

### 1.4 Extract Node Token

Required for the Windows Worker to join.

```bash
# Save securely! Do NOT commit.
multipass exec k3s-master -- sudo cat /var/lib/rancher/k3s/server/node-token
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
curl -fsSL [https://tailscale.com/install.sh](https://tailscale.com/install.sh) | sh

# 2. Authenticate
sudo tailscale up --authkey <YOUR_TS_AUTH_KEY> --hostname=k3s-worker-gpu

# 3. Get IP
WORKER_IP=$(tailscale ip -4)
```

> **Manual Action:** Go to Tailscale Admin Console -\> Machines -\> `k3s-worker-gpu` -\> **"Disable Key Expiry"**.

### 2.3 Join Cluster

Run this inside the WSL2 Ubuntu terminal:

```bash
# Variables (Replace with data from Step 1)
MASTER_IP="100.x.y.z"          
NODE_TOKEN="K10..."            

# Install K3s Agent
curl -sfL [https://get.k3s.io](https://get.k3s.io) | INSTALL_K3S_EXEC="agent \
  --server https://${MASTER_IP}:6443 \
  --token ${NODE_TOKEN} \
  --node-ip ${WORKER_IP} \
  --node-external-ip ${WORKER_IP} \
  --flannel-iface tailscale0" \
  sh -
```

-----

## 🗄 Step 3: Configure Storage (Synology NAS)

**Context:** The Synology is no longer a compute node. It serves as the persistent storage layer (NFS) for the cluster.

### 3.1 Enable NFS Service

1.  Log into Synology DSM.
2.  Go to **Control Panel** -\> **File Services** -\> **NFS**.
3.  Check **Enable NFS Service**.
4.  Set **Maximum NFS protocol** to `NFSv4.1`.

### 3.2 Create Shared Folder

1.  Go to **Control Panel** -\> **Shared Folder**.
2.  Create a new folder named `k8s-data`.
3.  **Edit** the folder -\> **NFS Permissions** tab -\> **Create**.
      * **Hostname/IP:** `*` (Or your Tailscale Subnet `100.64.0.0/10` for security).
      * **Privilege:** Read/Write.
      * **Squash:** Map all users to admin (Simplifies permission issues in home labs).
      * **Security:** `sys`.
      * **Tick:** Allow connections from non-privileged ports.

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
NAME             STATUS   ROLES                  AGE     VERSION        INTERNAL-IP   OS-IMAGE
k3s-master       Ready    control-plane,master   15m     v1.28.x+k3s1   100.x.x.x     Ubuntu 22.04
k3s-worker-gpu   Ready    <none>                 2m      v1.28.x+k3s1   100.y.y.y     Ubuntu 22.04
```

-----

## 🆘 Troubleshooting

**Symptoms:** Windows Worker cannot join.

1.  **Firewall:** Ensure Windows Defender isn't blocking the WSL network adapter.
2.  **Tailscale:** Ensure both `k3s-master` and `k3s-worker-gpu` can ping each other's 100.x IPs.
3.  **Logs:**
      * Master: `journalctl -u k3s -f`
      * Windows (WSL): `journalctl -u k3s-agent -f`

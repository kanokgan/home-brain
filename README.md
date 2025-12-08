# 🧠 HomeBrain: AI-Powered Home Operations Platform

![Status](https://img.shields.io/badge/Status-Active_Development-green)
![Tech](https://img.shields.io/badge/Stack-Golang_|_K3s_|_ArgoCD-blue)
![Architecture](https://img.shields.io/badge/Arch-Hybrid_(ARM64/AMD64)-orange)

**HomeBrain** is an Internal Developer Platform (IDP) designed to manage, aggregate, and query personal data (Finance, Media, Infrastructure) through a unified Golang API and Local LLM interface.

It transforms a standard Home Lab into a production-grade, Cloud-Native environment, replacing SaaS subscriptions (Google Photos, Dropbox, YNAB) with self-hosted, AI-enhanced alternatives.

## 🏗 Architecture

The system runs on a **Hybrid-Architecture Kubernetes Cluster** (K3s), utilizing the **"Brain & Muscle"** pattern to optimize for power efficiency and AI performance:

* **The Brain (Control Plane):** Mac Mini M2 (ARM64). Runs 24/7, handling the API, Orchestration, and lightweight apps. Low power consumption (~5W).
* **The Muscle (AI Worker):** Gaming PC (Intel i5/RTX 4060). Wakes on LAN to handle heavy AI Inference (Ollama/LLMs) and Batch Processing.
* **The Vault (Storage):** Synology DS923+. Provides persistent NFS storage for the cluster.

### Runtime Architecture

```mermaid
flowchart TB
 subgraph subGraph0["Public Internet"]
        CF["Cloudflare Tunnel"]
        TS["Tailscale Mesh"]
  end
 subgraph subGraph1["Master Node: Mac Mini M2 (ARM64)"]
        Ingress["Traefik Ingress"]
        GoApp["Golang Aggregator API"]
        Argocd["ArgoCD"]
        LocalSSD[("Local NVMe SSD")]
  end
 subgraph subGraph2["Worker Node 1: Windows PC (AMD64/WSL2)"]
        Ollama["Ollama (GPU Accelerated)"]
  end
 subgraph subGraph3["Worker Node 2: Ubuntu Extreme (AMD64)"]
        ImmichML["Immich ML Engine"]
        Workloads["Heavy Workloads"]
  end
 subgraph subGraph4["Cluster: K3s Hybrid"]
        subGraph1
        subGraph2
        subGraph3
  end
 subgraph subGraph5["Storage Appliance"]
        Synology["Synology DS923+"]
        NFS[("NFS Shares")]
  end
    User(("User")) --> CF & TS
    CF --> Ingress
    TS --> Ingress
    Ingress --> GoApp
    GoApp --> Ollama & ImmichML & LocalSSD
    GoApp -.-> NFS
    Argocd -.-> NFS
    ImmichML -.-> NFS
    Workloads -.-> NFS
```

### CI/CD Pipeline

```mermaid
graph LR
    subgraph "Dev Environment (M1 Mac)"
        Code[Golang Code] --> Git[Push to GitHub]
    end

    subgraph "CI Pipeline (GitHub Cloud)"
        Git --> Action[GitHub Action]
        Action -- Build ARM64 & AMD64 --> GHCR[GitHub Container Registry]
    end

    subgraph "The Cluster (Home Network)"
        subgraph "Control Plane (Mac Mini M2)"
            ArgoCD[ArgoCD Controller]
            Master[K3s Master]
        end

        subgraph "Compute Node (Windows PC)"
            Worker[K3s GPU Worker]
        end

        subgraph "Storage (Synology NAS)"
            NFS[(NFS Shares)]
        end
    end

    ArgoCD -- "1. Detects Change" --> Git
    ArgoCD -- "2. Pulls Manifest" --> Git
    Master -- "3. Pulls Image" --> GHCR
    Master -- "4. Deploys Pods" --> Worker
    Worker -- "5. Persists Data" --> NFS
```

## 🛠 Tech Stack

| Domain | Technology | Rationale |
| :--- | :--- | :--- |
| **Orchestration** | **K3s** | Lightweight Kubernetes distribution suitable for hybrid architectures. |
| **GitOps** | **ArgoCD** | Declarative continuous delivery; "Cluster as Code." |
| **Backend** | **Golang** | High-concurrency API gateway to aggregate disparate services. |
| **AI / ML** | **Ollama + NVIDIA** | Leveraging RTX 4060 (Tensor Cores) for fast local LLM inference. |
| **Networking** | **Tailscale** | Zero-trust Mesh VPN for secure Node-to-Node communication. |
| **Storage** | **NFS (Synology)** | Decoupled storage layer for persistent volumes. |

## 🚀 Infrastructure Runbook (Phase 1)

**Objective:** Provision the K3s Control Plane on the Mac Mini M2 using Multipass and Tailscale.

### 1\. Master Node Provisioning (Mac Mini M2)

We use **Multipass** to run a native ARM64 Ubuntu VM. This isolates the cluster from the macOS host while retaining native performance.

```bash
# 1. Launch the VM with Cloud-Init to pre-install Tailscale
multipass launch --name k3s-master \
  --cpus 2 \
  --memory 4G \
  --disk 20G \
  --cloud-init - <<EOF
package_update: true
package_upgrade: true
runcmd:
  - curl -fsSL https://tailscale.com/install.sh | sh
EOF

# 2. Authenticate Tailscale (Manual Step)
multipass exec k3s-master -- sudo tailscale up
# > Copy the auth link and approve in Tailscale Admin Console.
# > CRITICAL: Disable "Key Expiry" for this machine in Tailscale Console.
```

### 2\. K3s Installation (Tailscale Binding)

**Critical Architecture Decision:** We bind K3s explicitly to the `tailscale0` interface. This ensures that all Pod-to-Pod traffic is encrypted via WireGuard (Tailscale) and allows nodes on different physical networks (like the Windows PC) to join the cluster seamlessly.

```bash
# 1. Get the Tailscale IP
TS_IP=$(multipass exec k3s-master -- tailscale ip -4)
echo "Master IP: $TS_IP"  # Example: 100.x.x.x

# 2. Install K3s with Network Overrides
multipass exec k3s-master -- bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server \
  --node-ip ${TS_IP} \
  --node-external-ip ${TS_IP} \
  --flannel-iface tailscale0 \
  --disable traefik \
  --write-kubeconfig-mode 644' sh -"

# 3. Get the node token for worker registration
multipass exec k3s-master -- sudo cat /var/lib/rancher/k3s/server/node-token
# Save this token securely - needed for worker setup
```

### 3\. GPU Worker Node Setup (Windows PC with WSL2)

**Prerequisites:** WSL2 with Ubuntu 22.04 and systemd enabled

```bash
# On Windows in WSL2 Ubuntu terminal:

# 1. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=k3s-worker-gpu
# Follow auth link and disable key expiry in Tailscale console

# 2. Get Worker IP
WORKER_IP=$(tailscale ip -4)
echo "Worker IP: $WORKER_IP"  # Example: 100.y.y.y

# 3. Install NFS client (CRITICAL for storage)
sudo apt-get update
sudo apt-get install -y nfs-common

# 4. Join the cluster
# Replace MASTER_IP and K3S_TOKEN with values from Step 2
MASTER_IP="100.x.x.x"     # Your master Tailscale IP from step 2
K3S_TOKEN="K10..."         # Your token from step 2

curl -sfL https://get.k3s.io | \
  K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-external-ip=${WORKER_IP} \
    --flannel-iface=tailscale0 \
    --kubelet-arg=eviction-hard=imagefs.available<1% \
    --kubelet-arg=eviction-hard=nodefs.available<1%" sh -

# Note: WSL2-specific eviction settings required for proper disk capacity handling
```

### 4\. NFS Storage Setup (Synology NAS)

**Configure NFS share on Synology:**

1. Control Panel → File Services → Enable NFS
2. Control Panel → Shared Folder → Create `k3s-data`
3. NFS Permissions:
   - Server: `192.168.x.x` (Your Synology LAN IP)
   - Share path: `/volume1/k3s-data`
   - Allowed clients: `*` or `100.64.0.0/10` (Tailscale subnet)
   - Privilege: Read/Write
   - Squash: Map all users to admin
   - Enable: "Allow connections from non-privileged ports"

### 5\. Developer Access (Host Machine)

To control the cluster via VS Code on macOS:

```bash
# 1. Export Config
multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config-homebrain

# 2. Update IP (Replace localhost with Tailscale IP)
sed -i '' "s/127.0.0.1/$(multipass exec k3s-master -- tailscale ip -4)/g" ~/.kube/config-homebrain

# 3. Test Connection
export KUBECONFIG=~/.kube/config-homebrain
kubectl get nodes -o wide

# Expected output:
# NAME             STATUS   ROLES                  AGE   VERSION
# k3s-master       Ready    control-plane,master   ...   v1.33.6+k3s1
# <worker-hostname> Ready    <none>                 ...   v1.33.6+k3s1
```

## 🗺 Roadmap

This project is executed in three distinct engineering phases.

  - [x] **Phase 1: Infrastructure & GitOps** (✅ Complete)
      - [x] Provision K3s Master on Mac Mini M2
      - [x] Configure Windows PC as GPU Worker Node (via WSL2/Tailscale)
      - [x] Implement ArgoCD for automated application syncing
      - [x] Configure Synology as NFS Storage Provider
      - [ ] Setup Traefik Ingress Controller
      - [ ] Deploy monitoring stack (Prometheus/Grafana)
  - [ ] **Phase 2: The Aggregator Backend** (Golang/Gin) - Next
  - [ ] **Phase 3: The AI Agent** (Ollama/RAG with RTX 4060)

## 🔐 Security & Privacy

  * **Secrets Management:** No secrets are stored in this repo. We use `.env` files locally and Kubernetes Secrets/Sealed Secrets in production.
  * **Network:** No ports are forwarded on the router. All ingress is handled via encrypted Tunnels.
  * **Data:** All data resides locally on the NAS; no PII is sent to public AI APIs.

-----

*Author: Kanokgan - Senior Software Engineer specializing in Backend & Cloud-Native Systems.*
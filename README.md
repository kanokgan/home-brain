# HomeBrain: AI-Powered Home Operations Platform

![Status](https://img.shields.io/badge/Status-Active_Development-green)
![Tech](https://img.shields.io/badge/Stack-Golang_|_K3s_|_ArgoCD-blue)
![Architecture](https://img.shields.io/badge/Arch-Hybrid_(ARM64/AMD64)-orange)

**HomeBrain** is an Internal Developer Platform (IDP) designed to manage, aggregate, and query personal data (Finance, Media, Infrastructure) through a unified Golang API and Local LLM interface.

It transforms a standard Home Lab into a production-grade, Cloud-Native environment, replacing SaaS subscriptions (Google Photos, Dropbox, YNAB) with self-hosted, AI-enhanced alternatives.

## Architecture

The system runs on a **Hybrid-Architecture Kubernetes Cluster** (K3s), utilizing the **"Brain & Muscle"** pattern to optimize for power efficiency and AI performance:

* **The Brain (Control Plane):** Mac Mini M2 (ARM64). Runs 24/7, handling the API, Orchestration, and lightweight apps. Low power consumption (~5W).
* **The Muscle (GPU Worker):** Gaming PC (Intel i5/RTX 4060). Wakes on LAN to handle heavy AI Inference (Ollama/LLMs) and GPU-accelerated workloads.
* **The Workhorse (Compute Worker):** Lenovo X1 Extreme Gen2 (Intel i7/32GB RAM). Runs Ubuntu bare metal for CPU-intensive workloads and Immich ML processing.
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
 subgraph subGraph3["Worker Node 2: Lenovo X1 Extreme Gen2 (AMD64)"]
        ImmichML["Immich ML Engine"]
        Workloads["CPU-Intensive Workloads"]
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

### Network Architecture

```mermaid
---
config:
  layout: dagre
---
flowchart TB
 subgraph ISP_Layer["ISP Network (192.168.1.0/24)"]
        ISPRouter["True/Humax Router<br>Gateway: 192.168.1.1"]
  end
 subgraph Home_Core["Home Network (192.168.0.0/24)"]
        TPLink["TP-Link AXE5400<br>WAN IP: 192.168.1.10<br>LAN Gateway: 192.168.0.1"]
  end
    Internet["Public Internet"] --> CloudflareCDN["Cloudflare CDN/Edge"] & ISPRouter
    ISPRouter -- "Static WAN Link<br>(192.168.1.10)" --> TPLink
    TPLink -- LAN --> MasterNode["k3s-master<br>Mac Mini M2<br>LAN: 192.168.0.x<br>TS: 100.x.x.x"] & WorkerGPU["k3s-worker-gpu<br>Windows PC<br>LAN: 192.168.0.x<br>TS: 100.x.x.x"] & WorkerExtreme["k3s-worker-extreme<br>Lenovo X1 Extreme Gen2<br>LAN: 192.168.0.x<br>TS: 100.x.x.x"] & Synology["Synology NAS<br>LAN: 192.168.0.x<br>NFS Server"]
    CloudflareCDN -- Cloudflare Tunnel<br>(Bypasses Double NAT) --> MasterNode
    TailscaleRelay["Tailscale Mesh"] -. "WireGuard Overlay<br>(100.x.x.x)" .- MasterNode & WorkerGPU & WorkerExtreme
    MasterNode <-- K3s Traffic --> WorkerGPU & WorkerExtreme
    WorkerGPU <-- K3s Traffic --> WorkerExtreme
    MasterNode -- NFS Storage --> Synology
    WorkerGPU -- NFS Storage --> Synology
    WorkerExtreme -- NFS Storage --> Synology

    style CloudflareCDN fill:#ff9800
    style ISPRouter fill:#e0e0e0,stroke:#333,stroke-dasharray: 5 5
    style TPLink fill:#42a5f5,color:white
    style MasterNode fill:#e1f5ff
    style WorkerGPU fill:#fff4e1
    style WorkerExtreme fill:#fff4e1
    style Synology fill:#e8f5e9
    style TailscaleRelay fill:#9c27b0
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

## Tech Stack

| Domain | Technology | Rationale |
| :--- | :--- | :--- |
| **Orchestration** | **K3s** | Lightweight Kubernetes distribution suitable for hybrid architectures. |
| **GitOps** | **ArgoCD** | Declarative continuous delivery; "Cluster as Code." |
| **Backend** | **Golang** | High-concurrency API gateway to aggregate disparate services. |
| **AI / ML** | **Ollama + NVIDIA** | Leveraging RTX 4060 (Tensor Cores) for fast local LLM inference. |
| **Networking** | **Tailscale** | Zero-trust Mesh VPN for secure Node-to-Node communication. |
| **Storage** | **NFS (Synology)** | Decoupled storage layer for persistent volumes. |

## Quick Start

For detailed infrastructure setup instructions, see the [Infrastructure Runbook](docs/runbooks/01-infrastructure.md).

**TL;DR:**
1. Provision K3s master on Mac Mini M2 (via Multipass)
2. Join GPU worker node (Windows PC with RTX 4060)
3. Join compute worker node (Lenovo X1 Extreme Gen2)
4. Configure NFS storage (Synology DS923+)
5. Setup external access (Cloudflare Tunnel)

For step-by-step instructions with troubleshooting, refer to:
- [RB-001: Phase 1 Infrastructure Setup](docs/runbooks/01-infrastructure.md)
- [RB-003: Cloudflare Tunnel Setup](docs/runbooks/02-cloudflare-tunnel.md)

## Roadmap

This project is executed in three distinct engineering phases.

  - [x] **Phase 1: Infrastructure & GitOps** (✅ Complete)
      - [x] Provision K3s Master on Mac Mini M2
      - [x] Configure Windows PC as GPU Worker Node (via WSL2/Tailscale)
      - [x] Configure Lenovo X1 Extreme Gen2 as Compute Worker Node
      - [x] Implement ArgoCD for automated application syncing
      - [x] Configure Synology as NFS Storage Provider
      - [ ] Setup Traefik Ingress Controller
      - [ ] Deploy monitoring stack (Prometheus/Grafana)
  - [ ] **Phase 2: The Aggregator Backend** (Golang/Gin) - Next
  - [ ] **Phase 3: The AI Agent** (Ollama/RAG with RTX 4060)

## Security & Privacy

  * **Secrets Management:** No secrets are stored in this repo. We use `.env` files locally and Kubernetes Secrets/Sealed Secrets in production.
  * **Network:** No ports are forwarded on the router. All ingress is handled via encrypted Tunnels.
  * **Data:** All data resides locally on the NAS; no PII is sent to public AI APIs.

-----

*Author: Kanokgan - Senior Software Engineer specializing in Backend & Cloud-Native Systems.*
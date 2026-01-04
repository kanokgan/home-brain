# HomeBrain: AI-Powered Home Operations Platform

![Status](https://img.shields.io/badge/Status-Active_Development-green)
![Tech](https://img.shields.io/badge/Stack-Golang_|_K3s_|_Jellyfin-blue)
![Architecture](https://img.shields.io/badge/Arch-Hybrid_(ARM64/AMD64)-orange)

**HomeBrain** is an Internal Developer Platform (IDP) designed to manage, aggregate, and query personal data (Finance, Media, Infrastructure) through a unified Golang API and Local LLM interface.

It transforms a standard Home Lab into a production-grade, Cloud-Native environment, replacing SaaS subscriptions (Google Photos, Dropbox, YNAB) with self-hosted, AI-enhanced alternatives.

## Architecture

The system runs on a **Dual-Node K3s Cluster** with workload specialization:

* **k3s-master (Control Plane + GPU Workloads):** Lenovo X1 Extreme Gen2 (Intel i7-9750H 6C/12T, 32GB RAM, NVIDIA GTX 1650 Mobile 4GB). Ubuntu 24.04 LTS bare metal running K3s v1.33.6+k3s1. Handles GPU-intensive workloads (Immich, Jellyfin) with GPU time-slicing (4 virtual GPUs).
* **k3s-worker (API & LLM Workloads):** Mac Mini M2 (ARM64, 8GB RAM). OrbStack Ubuntu VM running K3s v1.34.3+k3s1. Dedicated to API services and future LLM inference workloads.
* **Storage:** 1.9TB local NVMe SSD for hot data (K3s local-path provisioner). NAS (Synology DS923+ at 192.168.0.243) mounted via CIFS/SMB 3.1.1 for external photo libraries and backups.

### Runtime Architecture

```mermaid
flowchart TB
 subgraph subGraph0["Public Internet"]
        CF["Cloudflare Tunnel"]
        TS["Tailscale Mesh"]
  end
 subgraph subGraph1["K3s Dual-Node Cluster"]
        subgraph subGraph2["k3s-master: Lenovo X1 Extreme Gen2 (x86_64)"]
            Immich["Immich Server"]
            Jellyfin["Jellyfin Server"]
            ImmichML["Immich ML (GPU)"]
            Postgres["PostgreSQL"]
            Redis["Redis"]
            ArgoCD["ArgoCD"]
            LocalNVMe[("Local NVMe 1.9TB")]
        end
        subgraph subGraph3["k3s-worker: Mac Mini M2 (ARM64)"]
            API["HomeBrain API"]
            LLM["Future: Ollama LLM"]
        end
  end
 subgraph subGraph4["Storage"]
        NAS["Synology DS923+ NAS"]
        SMB[("SMB Shares")]
  end
    User(("User")) --> CF & TS
    CF --> Immich & Jellyfin & API
    TS --> Immich & Jellyfin & API
    API --> Immich & Jellyfin
    Immich --> ImmichML & Postgres & Redis
    Immich --> LocalNVMe
    Immich -.-> SMB
    ImmichML -.-> SMB
    ArgoCD -. "GitOps" .-> API
```

### Network Architecture

```mermaid
flowchart TB
 subgraph ISP_Layer["ISP Network (192.168.1.0/24)"]
        ISPRouter["True/Humax Router<br>Gateway: 192.168.1.1"]
  end
 subgraph Home_Core["Home Network (192.168.0.0/24)"]
        TPLink["TP-Link AXE5400<br>WAN IP: 192.168.1.10<br>LAN Gateway: 192.168.0.1"]
  end
    Internet["Public Internet"] --> CloudflareCDN["Cloudflare CDN/Edge"] & ISPRouter
    ISPRouter -- "Static WAN Link<br>(192.168.1.10)" --> TPLink
    TPLink -- LAN --> K3sMaster["k3s-master<br>Lenovo X1 Extreme Gen2<br>LAN: 192.168.0.206<br>TS: 100.81.236.27"] & K3sWorker["k3s-worker<br>Mac Mini M2 (OrbStack)<br>LAN: 192.168.0.x<br>TS: 100.x.x.x"] & NAS["Synology DS923+ NAS<br>LAN: 192.168.0.243<br>TS: 100.77.209.53"]
    CloudflareCDN -- Cloudflare Tunnel<br>(Active) --> K3sMaster
    TailscaleRelay["Tailscale Mesh"] -. "WireGuard Overlay<br>(100.x.x.x)" .- K3sMaster & K3sWorker & NAS
    K3sMaster -- SMB Storage --> NAS
    K3sMaster <--> K3sWorker

    style CloudflareCDN fill:#ff9800
    style ISPRouter fill:#e0e0e0,stroke:#333,stroke-dasharray: 5 5
    style TPLink fill:#42a5f5,color:white
    style K3sMaster fill:#e1f5ff
    style K3sWorker fill:#c8e6c9
    style NAS fill:#e8f5e9
    style TailscaleRelay fill:#9c27b0
```

### CI/CD Pipeline

```mermaid
graph LR
    subgraph "Dev Environment (M1 Mac)"
        Code[Configuration] --> Git[Push to GitHub]
    end

    subgraph "GitOps (Planned)"
        Git --> ArgoCD[ArgoCD]
    end

    subgraph "K3s Cluster (k3s-master)"
        ArgoCD -- "Sync Manifests" --> K3s[K3s Control Plane]
        K3s -- "Deploy Pods" --> Apps[Applications]
        Apps -- "Persist Data" --> Storage[(Local NVMe + NAS)]
    end
```

## Tech Stack

| Domain | Technology | Rationale |
| :--- | :--- | :--- |
| **Orchestration** | **K3s** | Lightweight Kubernetes distribution. Dual-node: k3s-master (x86_64) + k3s-worker (ARM64). |
| **Backend API** | **Golang (Gin) + Docker (Multi-arch)** | HomeBrain API for service health monitoring and aggregation. Deployed on ARM64 worker node. |
| **Applications** | **Immich + Jellyfin** | Self-hosted photo/media management with GPU-accelerated ML (face recognition, CLIP embeddings, transcoding). |
| **GitOps** | **ArgoCD** | Automated deployment and sync from GitHub. Manages HomeBrain API and future services. |
| **AI / ML** | **CUDA + NVIDIA GTX 1650 (4x time-sliced)** | GPU acceleration for Immich ML (face recognition, CLIP), Jellyfin transcoding, and Immich video encoding. Future: Ollama LLM on ARM64 worker. |
| **Networking** | **Tailscale + Cloudflare Tunnel** | Zero-trust mesh VPN for private access (*.dove-komodo.ts.net), Cloudflare Tunnel for public access (*.kanokgan.com). No traditional ingress controller - Traefik disabled. |
| **Storage** | **Local NVMe + CIFS** | 1.9TB local NVMe for hot data (K3s local-path), Synology DS923+ NAS via optimized CIFS mounts for read-only external libraries. |

## Quick Start

For detailed infrastructure setup instructions, see the [Infrastructure Runbook](docs/runbooks/01-infrastructure.md).

**Current Deployment:**
1. ✅ K3s dual-node cluster: k3s-master v1.33.6 (x86_64) + k3s-worker v1.34.3 (ARM64/Mac Mini M2 via OrbStack)
2. ✅ NVIDIA GPU support with Container Toolkit and device plugin (4x virtual GPUs via time-slicing)
3. ✅ Immich photo management with GPU-accelerated ML (2 GPU slices: server + ML)
4. ✅ Jellyfin media server with GPU transcoding (2 GPU slices)
5. ✅ HomeBrain API (Golang/Gin) on k3s-worker - service health monitoring for Immich/Jellyfin
6. ✅ ArgoCD for GitOps deployment automation
7. ✅ Redis with AOF persistence + ML model cache (persistent storage)
8. ✅ Tailscale mesh for secure private access (HTTPS on *.dove-komodo.ts.net)
9. ✅ Cloudflare Tunnel for public access (*.kanokgan.com)
10. ✅ Monitoring stack: Prometheus, Grafana, Promtail, node-exporter (Loki available but scaled to 0)
11. ✅ Filebrowser for SSD/NAS management via Tailscale

For step-by-step instructions with troubleshooting, refer to:
- [RB-001: Infrastructure Setup](docs/runbooks/01-infrastructure.md)
- [RB-002: Cloudflare Tunnel Setup](docs/runbooks/02-cloudflare-tunnel.md)
- [RB-003: GPU Configuration](docs/runbooks/03-gpu-configuration.md)
- [RB-004: Immich Deployment](docs/runbooks/04-immich-deployment.md)
- [RB-005: Jellyfin Deployment](docs/runbooks/05-jellyfin-deployment.md)

## Roadmap

This project is executed in distinct engineering phases.

  - [x] **Phase 1: Infrastructure & Core Services** (Complete)
      - [x] Provision K3s single-node cluster on Ubuntu 24.04
      - [x] Add k3s-worker node (Mac Mini M2, ARM64 via OrbStack)
      - [x] Configure NVIDIA GPU support (GTX 1650 with 4x time-slicing)
      - [x] Disable Traefik - use Cloudflare Tunnel + Tailscale instead
      - [x] Configure Synology NAS with optimized CIFS mounts (SMB 3.1.1, 128KB buffers)
      - [x] Setup security: Pod Security Standards, RBAC
      - [x] Deploy Immich with GPU-accelerated ML + persistent Redis/ML cache
      - [x] Deploy Jellyfin with GPU transcoding
      - [x] Complete Tailscale HTTPS access (*.dove-komodo.ts.net)
      - [x] Setup Cloudflare tunnel (*.kanokgan.com)
      - [x] Deploy Filebrowser for file management
      - [x] Deploy monitoring stack (Prometheus/Grafana/Promtail)
      - [ ] Re-enable Loki for log aggregation
      - [ ] Implement automated backups to NAS
  - [x] **Phase 2: GitOps & API Development** (In Progress - 60% Complete)
      - [x] Deploy ArgoCD for GitOps workflow
      - [x] Build HomeBrain API (Golang/Gin) with multi-arch Docker support
      - [x] Implement service health monitoring (Immich, Jellyfin)
      - [x] Deploy API to k3s-worker via ArgoCD
      - [ ] Setup automated image updates
      - [ ] Add Tailscale access for API
      - [ ] Extend API with Immich query capabilities
  - [ ] **Phase 3: Additional Services**
      - [ ] Deploy Ollama for local LLM inference
      - [ ] Add financial tracking (YNAB alternative)
      - [ ] Build Golang aggregator API

## Security & Privacy

  * **Secrets Management:** No secrets are stored in this repo. We use `.env` files locally and Kubernetes Secrets/Sealed Secrets in production.
  * **Network:** No ports are forwarded on the router. All ingress is handled via encrypted Tunnels.
  * **Data:** All data resides locally on the NAS; no PII is sent to public AI APIs.

-----

*Author: Kanokgan - Senior Software Engineer specializing in Backend & Cloud-Native Systems.*
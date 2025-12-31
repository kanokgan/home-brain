# HomeBrain: AI-Powered Home Operations Platform

![Status](https://img.shields.io/badge/Status-Active_Development-green)
![Tech](https://img.shields.io/badge/Stack-Golang_|_K3s_|_Jellyfin-blue)
![Architecture](https://img.shields.io/badge/Arch-Hybrid_(ARM64/AMD64)-orange)

**HomeBrain** is an Internal Developer Platform (IDP) designed to manage, aggregate, and query personal data (Finance, Media, Infrastructure) through a unified Golang API and Local LLM interface.

It transforms a standard Home Lab into a production-grade, Cloud-Native environment, replacing SaaS subscriptions (Google Photos, Dropbox, YNAB) with self-hosted, AI-enhanced alternatives.

## Architecture

The system runs on a **Single-Node K3s Cluster** optimized for self-hosted applications with GPU acceleration:

* **K3s Master Node:** Lenovo X1 Extreme Gen2 (Intel i7-9750H/32GB RAM/NVIDIA GTX 1650). Ubuntu 24.04 LTS bare metal running K3s v1.33.6. Handles all workloads with GPU acceleration for ML tasks.
* **Storage:** 1.9TB local NVMe SSD for high-performance storage. NAS (Synology DS923+) mounted via SMB for external libraries and backups.

### Runtime Architecture

```mermaid
flowchart TB
 subgraph subGraph0["Public Internet"]
        CF["Cloudflare Tunnel"]
        TS["Tailscale Mesh"]
  end
 subgraph subGraph1["K3s Single Node Cluster"]
        subgraph subGraph2["k3s-master: Lenovo X1 Extreme Gen2"]
            Immich["Immich Server"]
            Jellyfin["Jellyfin Server"]
            ImmichML["Immich ML (GPU)"]
            Postgres["PostgreSQL"]
            Redis["Redis"]
            LocalNVMe[("Local NVMe 1.9TB")]
        end
  end
 subgraph subGraph3["Storage"]
        NAS["Synology DS923+ NAS"]
        SMB[("SMB Shares")]
  end
    User(("User")) --> CF & TS
    CF --> Immich & Jellyfin
    TS --> Immich & Jellyfin
    Immich --> ImmichML & Postgres & Redis
    Immich --> LocalNVMe
    Immich -.-> SMB
    ImmichML -.-> SMB
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
    TPLink -- LAN --> K3sMaster["k3s-master<br>Lenovo X1 Extreme Gen2<br>LAN: 192.168.0.206<br>TS: 100.81.236.27"] & NAS["Synology DS923+ NAS<br>LAN: 192.168.0.x<br>TS: 100.77.209.53"]
    CloudflareCDN -- Cloudflare Tunnel<br>(Planned) --> K3sMaster
    TailscaleRelay["Tailscale Mesh"] -. "WireGuard Overlay<br>(100.x.x.x)" .- K3sMaster & NAS
    K3sMaster -- SMB Storage --> NAS

    style CloudflareCDN fill:#ff9800
    style ISPRouter fill:#e0e0e0,stroke:#333,stroke-dasharray: 5 5
    style TPLink fill:#42a5f5,color:white
    style K3sMaster fill:#e1f5ff
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
| **Orchestration** | **K3s** | Lightweight Kubernetes distribution for single-node deployment. |
| **Applications** | **Immich** | Self-hosted photo management with GPU-accelerated ML (face recognition, CLIP embeddings). |
| **AI / ML** | **CUDA + NVIDIA GTX 1650** | GPU acceleration for machine learning workloads. |
| **Networking** | **Tailscale + Cloudflare Tunnel** | Zero-trust mesh VPN for private access, Cloudflare Tunnel for public access. No traditional ingress controller. |
| **Storage** | **Local NVMe + NFS** | 1.9TB local NVMe for hot data, NAS for media libraries and backups. |

## Quick Start

For detailed infrastructure setup instructions, see the [Infrastructure Runbook](docs/runbooks/01-infrastructure.md).

**Current Deployment:**
1. ✅ K3s v1.33.6 on Ubuntu 24.04 LTS (Lenovo X1 Extreme Gen2) with Traefik disabled
2. ✅ NVIDIA GPU support with Container Toolkit and device plugin (4x virtual GPUs via time-slicing)
3. ✅ Immich photo management with GPU-accelerated ML (514GB data migrated)
4. ✅ Jellyfin media server with GPU transcoding (3x GPUs)
5. ✅ Tailscale mesh for secure private access (HTTPS on *.dove-komodo.ts.net)
6. ✅ Cloudflare Tunnel for public access (immich.kanokgan.com, jellyfin.kanokgan.com, argocd.kanokgan.com)
7. ✅ Filebrowser for SSD/NAS management via Tailscale

For step-by-step instructions with troubleshooting, refer to:
- [RB-001: Infrastructure Setup](docs/runbooks/01-infrastructure.md)
- [RB-002: Cloudflare Tunnel Setup](docs/runbooks/02-cloudflare-tunnel.md)
- [RB-003: Immich Deployment](docs/runbooks/03-immich-deployment.md)
- [Quick Setup: Cloudflare Tunnel](docs/CLOUDFLARE_TUNNEL_SETUP.md)

## Roadmap

This project is executed in distinct engineering phases.

  - [x] **Phase 1: Infrastructure & Core Services** (95% Complete)
      - [x] Provision K3s single-node cluster on Ubuntu 24.04
      - [x] Configure NVIDIA GPU support (GTX 1650 with 4x time-slicing)
      - [x] Disable Traefik - use Cloudflare Tunnel + Tailscale instead
      - [x] Configure Synology NAS as NFS storage
      - [x] Setup security: Pod Security Standards, RBAC, Network Policies
      - [x] Deploy Immich with GPU-accelerated ML
      - [x] Deploy Jellyfin with GPU transcoding
      - [x] Migrate 514GB production data from Docker
      - [x] Complete Tailscale HTTPS access (*.dove-komodo.ts.net)
      - [x] Setup Cloudflare tunnel (*.kanokgan.com)
      - [x] Deploy Filebrowser for file management
      - [ ] Deploy monitoring stack (Prometheus/Grafana)
      - [ ] Implement automated backups to NAS
  - [ ] **Phase 2: GitOps & Automation** - Next
      - [ ] Deploy ArgoCD for GitOps workflow
      - [ ] Setup automated image updates
      - [ ] Implement Infrastructure as Code for all services
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
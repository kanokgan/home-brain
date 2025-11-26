# 🧠 HomeBrain: AI-Powered Home Operations Platform

![Status](https://img.shields.io/badge/Status-Active_Development-green)
![Tech](https://img.shields.io/badge/Stack-Golang_|_K3s_|_ArgoCD-blue)
![Architecture](https://img.shields.io/badge/Arch-Hybrid_(ARM64/AMD64)-orange)

**HomeBrain** is an Internal Developer Platform (IDP) designed to manage, aggregate, and query personal data (Finance, Media, Infrastructure) through a unified Golang API and Local LLM interface.

It transforms a standard Home Lab into a production-grade, Cloud-Native environment, replacing SaaS subscriptions (Google Photos, Dropbox, YNAB) with self-hosted, AI-enhanced alternatives.

## 🏗 Architecture

The system runs on a **Hybrid-Architecture Kubernetes Cluster** (K3s), leveraging the specific strengths of heterogeneous hardware:
* **Control Plane & AI Compute:** Mac Mini M2 (ARM64) for high-speed API response and Neural Engine access.
* **Storage & Workloads:** Synology DS923+ (AMD64) via VM for persistent storage and legacy container compatibility.

```mermaid
graph TD
    subgraph "Public Internet"
        CF[Cloudflare Tunnel]
        TS[Tailscale Mesh]
    end

    subgraph "Cluster: K3s Hybrid"
        subgraph "Node: Mac Mini M2 (ARM64)"
            Ingress[Traefik Ingress]
            GoApp[Golang Aggregator API]
            Ollama[Ollama / Local LLM]
        end

        subgraph "Node: Synology NAS (AMD64)"
            Postgres[(PostgreSQL)]
            Immich[Immich Service]
            Budget[Actual Budget]
            Jellyfin[Jellyfin Media]
        end
    end

    User((User)) --> CF --> Ingress
    User --> TS --> Ingress
    Ingress --> GoApp
    GoApp --> Immich
    GoApp --> Budget
    GoApp --> Ollama
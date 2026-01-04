# Infrastructure as Code

This directory contains all Kubernetes infrastructure configurations for the HomeBrain platform.

## Directory Structure

```
infrastructure/
├── argocd/              # GitOps - ArgoCD configuration
│   ├── helm-values.yaml # Helm chart values
│   ├── apps/            # Application manifests
│   │   ├── example-app.yaml
│   │   └── homebrain-api.yaml
│   └── README.md
├── cloudflare/          # Cloudflare Tunnel for public external access
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── configmap.yaml
│   └── README.md
├── monitoring/          # Prometheus, Grafana, Loki
└── storage/             # NFS provisioner, PVCs
```

## Deployment Order

1. **Storage** - CIFS mounts + local-path provisioner (✅ Configured)
2. **GPU** - NVIDIA device plugin with time-slicing (✅ Deployed on k3s-master)
3. **Worker Node** - k3s-worker (Mac Mini M2, ARM64) (✅ Joined)
4. **Cloudflare** - Tunnel for secure public access (✅ Deployed)
5. **Monitoring** - Observability stack (✅ Deployed, Loki scaled to 0)
6. **ArgoCD** - GitOps engine (✅ Deployed, actively managing apps)
7. **Applications** - Services (Immich, Jellyfin, HomeBrain API) (✅ Deployed)

## Network Architecture

**Dual-Node Cluster:**
- **k3s-master:** Lenovo X1 Extreme Gen2 (x86_64, NVIDIA GPU)
- **k3s-worker:** Mac Mini M2 (ARM64 via OrbStack)

**Access Methods:**
- **Public Access:** Cloudflare Tunnel (immich.kanokgan.com, jellyfin.kanokgan.com, argocd.kanokgan.com)
- **Private Access:** Tailscale mesh VPN (*.dove-komodo.ts.net with HTTPS)
- **No Traditional Ingress:** K3s Traefik disabled - all routing via Cloudflare Tunnel + Tailscale sidecars
- **Service Type:** All services use ClusterIP (no LoadBalancer/NodePort)

**Resource Allocation:**
- **k3s-master:** GPU workloads (Immich, Jellyfin), databases (PostgreSQL, Redis), ArgoCD
- **k3s-worker:** API services (HomeBrain API), future LLM inference (Ollama)
- **GPU:** NVIDIA GTX 1650 Mobile with 4x time-slicing for shared GPU access

## Prerequisites

- K3s dual-node cluster running:
  - **k3s-master:** Control plane + worker (x86_64)
  - **k3s-worker:** Worker node (ARM64)
- kubectl configured with cluster access
- Helm 3.x installed
- Tailscale network configured
- OrbStack installed on Mac Mini M2 (for k3s-worker)

## Management

All infrastructure is managed through:
1. **Helm** - Initial installation
2. **ArgoCD** - Ongoing GitOps reconciliation
3. **Git** - Single source of truth

## Security Notes

- No secrets are stored in this repository
- Use Kubernetes Secrets or Sealed Secrets for sensitive data
- All nodes communicate via Tailscale encrypted mesh

# Infrastructure as Code

This directory contains all Kubernetes infrastructure configurations for the HomeBrain platform.

## Directory Structure

```
infrastructure/
├── argocd/              # GitOps - ArgoCD configuration
│   ├── helm-values.yaml # Helm chart values
│   ├── apps/            # Application manifests
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

1. **ArgoCD** - GitOps engine (✅ Deployed)
2. **Storage** - NFS provisioner for Synology (✅ Deployed)
3. **Cloudflare** - Tunnel for secure public access (✅ Deployed)
4. **Monitoring** - Observability stack (⏳ In Progress)
5. **Applications** - Actual services (Immich, Jellyfin, etc.) (✅ Deployed)

## Network Architecture

- **Public Access:** Cloudflare Tunnel (immich.kanokgan.com, jellyfin.kanokgan.com, argocd.kanokgan.com)
- **Private Access:** Tailscale mesh VPN (*.dove-komodo.ts.net with HTTPS)
- **No Traditional Ingress:** K3s Traefik is disabled - all routing via Cloudflare/Tailscale
- **Service Type:** All services use ClusterIP (no LoadBalancer/NodePort)

## Prerequisites

- K3s cluster running (control plane + worker nodes)
- kubectl configured with cluster access
- Helm 3.x installed
- Tailscale network configured

## Management

All infrastructure is managed through:
1. **Helm** - Initial installation
2. **ArgoCD** - Ongoing GitOps reconciliation
3. **Git** - Single source of truth

## Security Notes

- No secrets are stored in this repository
- Use Kubernetes Secrets or Sealed Secrets for sensitive data
- All nodes communicate via Tailscale encrypted mesh

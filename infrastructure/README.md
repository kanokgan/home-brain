# Infrastructure as Code

This directory contains all Kubernetes infrastructure configurations for the HomeBrain platform.

## Directory Structure

```
infrastructure/
├── argocd/              # GitOps - ArgoCD configuration
│   ├── helm-values.yaml # Helm chart values
│   ├── apps/            # Application manifests
│   └── README.md
├── cloudflare/          # Cloudflare Tunnel for external access
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── configmap.yaml
│   └── README.md
├── ingress/             # Traefik ingress controller
├── monitoring/          # Prometheus, Grafana, Loki
└── storage/             # NFS provisioner, PVCs
```

## Deployment Order

1. **ArgoCD** - GitOps engine (✅ Deployed)
2. **Storage** - NFS provisioner for Synology (✅ Deployed)
3. **Cloudflare** - Tunnel for secure external access (🚧 In Progress)
4. **Ingress** - Traefik for external access
5. **Monitoring** - Observability stack
6. **Applications** - Actual services (Immich, Actual Budget, etc.)

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

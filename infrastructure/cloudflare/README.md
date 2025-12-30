# Cloudflare Tunnel Configuration

This directory contains Kubernetes manifests for Cloudflare Tunnel integration, enabling secure external access to internal services without exposing ports.

## Architecture

```
Internet → cloudflare.com → Cloudflare Tunnel (cloudflared) → K3s Services
```

## Services Exposed

- **Immich**: `immich.kanokgan.com` → `immich-server.immich.svc.cluster.local:80`
- **ArgoCD**: `argocd.kanokgan.com` → `argocd-server.argocd.svc.cluster.local:80`

## Prerequisites

1. Cloudflare account with `kanokgan.com` domain
2. Cloudflare Tunnel created in Zero Trust dashboard
3. Tunnel token (stored as Kubernetes secret)

## Setup Instructions

See the runbook: `docs/runbooks/02-cloudflare-tunnel.md`

## Security

- All tunnel credentials are stored as Kubernetes secrets (not in Git)
- Tunnel token stored in `cloudflare-tunnel-credentials` secret
- Routing configuration managed via Cloudflare Dashboard (not in ConfigMap)
- Cloudflare Access can be enabled for additional authentication
- No inbound ports opened on home network
- Uses HTTP/2 protocol (TCP) instead of QUIC (UDP) for better compatibility

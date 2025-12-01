# Ingress Configuration

## Overview

Traefik is used as the ingress controller for external access to services.

## Access Methods

1. **Cloudflare Tunnel** - Public access with zero-trust security
2. **Tailscale** - VPN access for internal services
3. **Local Network** - Direct access when on home network

## Setup Tasks

- [ ] Install Traefik via Helm
- [ ] Configure IngressRoute CRDs
- [ ] Setup TLS certificates
- [ ] Configure Cloudflare Tunnel
- [ ] Add middleware (auth, rate limiting)

## Planned Routes

- `api.homebrain.internal` - Golang Aggregator API
- `argocd.homebrain.internal` - ArgoCD UI
- `photos.homebrain.internal` - Immich
- `budget.homebrain.internal` - Actual Budget
- `media.homebrain.internal` - Jellyfin

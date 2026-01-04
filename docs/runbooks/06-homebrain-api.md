# Runbook RB-006: HomeBrain API Deployment

| Field | Value |
|-------|-------|
| Status | Active |
| Version | v0.2.0 |
| Updated | 2026-01-04 |
| Node | k3s-worker (ARM64) |
| Language | Go 1.24 |

## Overview

HomeBrain API is a Golang microservice providing:
- Service health monitoring (Immich, Jellyfin)
- Centralized API gateway for all home-brain services
- Future: LLM-powered queries and aggregation

**Architecture:**
- **Language:** Go 1.24 with Gin web framework
- **Deployment:** Multi-arch Docker image (ARM64 + AMD64)
- **Container Registry:** GitHub Container Registry (ghcr.io/kanokgan/homebrain-api)
- **GitOps:** ArgoCD automated deployment
- **Target Node:** k3s-worker (Mac Mini M2, ARM64)

## API Endpoints

### Health Check
```bash
GET /health
```
**Response:**
```json
{
  "status": "alive",
  "version": "0.2.0",
  "system": "home-brain"
}
```

### Service Status
```bash
GET /api/services
```
**Response:**
```json
{
  "timestamp": "2026-01-04T12:00:00Z",
  "services": {
    "immich": {
      "healthy": true,
      "status": "healthy",
      "url": "https://immich.kanokgan.com"
    },
    "jellyfin": {
      "healthy": true,
      "status": "healthy",
      "url": "https://jellyfin.kanokgan.com"
    }
  }
}
```

### Individual Service Health
```bash
GET /api/services/immich
GET /api/services/jellyfin
```
**Response:**
```json
{
  "service": "immich",
  "healthy": true,
  "status": "healthy",
  "url": "https://immich.kanokgan.com"
}
```

## Deployment

### Prerequisites

1. **k3s-worker node joined to cluster:**
```bash
kubectl get nodes
# Should show k3s-worker Ready
```

2. **Node labels applied:**
```bash
kubectl label node k3s-worker workload-type=api-llm
kubectl label node k3s-worker kubernetes.io/arch=arm64
```

3. **Docker image published to GHCR:**
```bash
# From development machine (M1 Mac)
cd /Users/kanokgan/Developer/personal/home-brain
./scripts/build-api.sh
```

### Deployment via ArgoCD

1. **Commit code changes:**
```bash
git add backend/ k8s/backend/ infrastructure/argocd/apps/homebrain-api.yaml
git commit -m "feat: Add homebrain-api v0.2.0"
git push origin main
```

2. **Deploy ArgoCD Application:**
```bash
kubectl apply -f infrastructure/argocd/apps/homebrain-api.yaml
```

3. **Verify deployment:**
```bash
# Watch pod creation
kubectl get pods -n homebrain -w

# Check pod scheduled on correct node
kubectl get pods -n homebrain -o wide
# Should show NODE: k3s-worker

# Check logs
kubectl logs -n homebrain deployment/homebrain-api --tail=50
```

### Manual Deployment (Without ArgoCD)

```bash
# Apply manifests directly
kubectl apply -f k8s/backend/namespace.yaml
kubectl apply -f k8s/backend/deployment.yaml

# Watch deployment
kubectl get pods -n homebrain -w
```

## Development

### Local Development Setup

1. **Install Go 1.24:**
```bash
# On M1 Mac
brew install go@1.24
go version  # Should show go1.24.x
```

2. **Run locally:**
```bash
cd backend
go mod download
go run cmd/server/main.go

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/api/services
```

### Build Multi-arch Docker Image

```bash
# From project root
./scripts/build-api.sh

# Or manually:
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ghcr.io/kanokgan/homebrain-api:latest \
  --push \
  --file backend/Dockerfile \
  backend/
```

### Code Structure

```
backend/
├── cmd/
│   └── server/
│       └── main.go          # Main application entry point
├── Dockerfile               # Multi-arch container build
├── go.mod                   # Go dependencies
└── go.sum                   # Dependency checksums
```

**Key Functions:**
- `checkServiceHealth(url, timeout)` - Generic HTTP health probe
- `GET /health` - Kubernetes liveness/readiness probe
- `GET /api/services` - Aggregated service status
- `GET /api/services/{service}` - Individual service health

## Monitoring

### Check Pod Health

```bash
# Get pod status
kubectl get pods -n homebrain

# Describe pod for events
kubectl describe pod -n homebrain <pod-name>

# Check logs
kubectl logs -n homebrain deployment/homebrain-api --tail=100 -f
```

### Test API Endpoints

```bash
# Port-forward to test locally
kubectl port-forward -n homebrain svc/homebrain-api 8080:80

# Test endpoints
curl http://localhost:8080/health | jq
curl http://localhost:8080/api/services | jq
curl http://localhost:8080/api/services/immich | jq
curl http://localhost:8080/api/services/jellyfin | jq
```

### Check Resource Usage

```bash
# CPU and memory usage
kubectl top pod -n homebrain

# Resource requests vs limits
kubectl describe pod -n homebrain <pod-name> | grep -A 5 "Requests:"
```

## Configuration

### Kubernetes Manifests

**Location:** `k8s/backend/`

**deployment.yaml key settings:**
```yaml
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    spec:
      nodeSelector:
        workload-type: api-llm
        kubernetes.io/arch: arm64
      containers:
      - name: api
        image: ghcr.io/kanokgan/homebrain-api:latest
        env:
        - name: TZ
          value: "Asia/Bangkok"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
```

### ArgoCD Configuration

**Location:** `infrastructure/argocd/apps/homebrain-api.yaml`

```yaml
spec:
  project: default
  source:
    repoURL: https://github.com/kanokgan/home-brain
    targetRevision: main
    path: k8s/backend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Troubleshooting

### Pod Not Scheduling

**Symptom:** Pod stuck in Pending state

**Check:**
```bash
kubectl describe pod -n homebrain <pod-name> | grep -A 10 Events
```

**Common causes:**
- Node selector not matching any nodes
- Insufficient resources on k3s-worker
- Image pull errors

**Fix:**
```bash
# Verify node labels
kubectl get nodes --show-labels | grep workload-type

# Check node resources
kubectl describe node k3s-worker | grep -A 10 "Allocated resources"
```

### Image Pull Errors

**Symptom:** `ErrImagePull` or `ImagePullBackOff`

**Check:**
```bash
kubectl describe pod -n homebrain <pod-name> | grep -A 5 "Failed to pull"
```

**Common causes:**
- Container image is private (not public on GHCR)
- Wrong image name or tag
- Registry authentication required

**Fix:**
```bash
# Make GHCR package public
# Go to: https://github.com/users/kanokgan/packages/container/homebrain-api/settings
# Change visibility to Public

# Or verify image exists
docker pull ghcr.io/kanokgan/homebrain-api:latest
```

### Service Health Checks Failing

**Symptom:** API returns unhealthy status for Immich/Jellyfin

**Check:**
```bash
# Test from within pod
kubectl exec -n homebrain deployment/homebrain-api -- sh -c \
  "wget -qO- http://immich-server.immich.svc.cluster.local/api/server-info/ping"
```

**Common causes:**
- Service not running
- Wrong service DNS name
- Network policy blocking traffic

**Fix:**
```bash
# Verify services are running
kubectl get svc -n immich
kubectl get svc -n jellyfin

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup immich-server.immich.svc.cluster.local
```

### ArgoCD Sync Issues

**Symptom:** ArgoCD shows "OutOfSync" or sync fails

**Check ArgoCD:**
```bash
# Check app status
kubectl get application -n argocd homebrain-api -o yaml

# Check sync status
kubectl describe application -n argocd homebrain-api
```

**Manual sync:**
```bash
# Via kubectl
kubectl patch application -n argocd homebrain-api \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main"}}}' \
  --type merge

# Or via ArgoCD UI
# Visit: https://argocd.kanokgan.com
```

## Future Enhancements

- [ ] Add Tailscale sidecar for external API access
- [ ] Implement Immich photo query endpoints
- [ ] Add Ollama LLM integration for AI-powered queries
- [ ] Implement caching layer (Redis)
- [ ] Add authentication and API keys
- [ ] Create OpenAPI/Swagger documentation
- [ ] Add metrics endpoint for Prometheus
- [ ] Implement rate limiting

## See Also

- [RB-001: Infrastructure Setup](01-infrastructure.md)
- [RB-004: Immich Deployment](04-immich-deployment.md)
- [RB-005: Jellyfin Deployment](05-jellyfin-deployment.md)

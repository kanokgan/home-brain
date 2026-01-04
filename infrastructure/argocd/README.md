# ArgoCD Installation

## Current Status

✅ **Active GitOps:** ArgoCD is installed and actively managing applications via automated sync from GitHub.

**Access:**
- **Tailscale:** https://argocd-1.dove-komodo.ts.net
- **Cloudflare:** https://argocd.kanokgan.com

**Managed Applications:**
- ✅ **homebrain-api** - Service health monitoring API (deployed to k3s-worker)

**Future Applications:**
- 🔄 Immich (manual for now)
- 🔄 Jellyfin (manual for now)
- 🔄 Monitoring stack (manual for now)

## Installation

ArgoCD was installed on the K3s cluster using Helm:

```bash
# 1. Add Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Create namespace
kubectl create namespace argocd

# 3. Install ArgoCD
helm install argocd argo/argo-cd \
  --namespace argocd \
  -f helm-values.yaml
```

## Tailscale Integration

See [server-deployment.yaml](server-deployment.yaml) for complete configuration.

Key aspects:
- Tailscale sidecar runs alongside argocd-server
- State persisted via TS_KUBE_SECRET in Kubernetes secret
- Hostname: argocd
- Auth key stored in secret `tailscale-auth`

## Configuration

See `helm-values.yaml` for the custom configuration:
- All components pinned to `k3s-master` node
- HA mode disabled (single-node deployment for home lab)

## Access

### Tailscale (Primary)

https://argocd-1.dove-komodo.ts.net

Admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### CLI Access

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward (if not using Tailscale)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login via CLI
argocd login argocd-1.dove-komodo.ts.net --username admin
```

### Web UI

After port-forwarding, access at: https://localhost:8080

## Verification

```bash
# Check pods
kubectl get pods -n argocd

# Check service
kubectl get svc -n argocd
```

## Application Deployment

Applications are managed via manifests in `apps/` directory. Each application is deployed as an ArgoCD Application CRD with automated sync enabled.

### Deploy a New Application

1. **Create ArgoCD Application manifest:**
```yaml
# Example: apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kanokgan/home-brain
    targetRevision: main
    path: k8s/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

2. **Apply the application:**
```bash
kubectl apply -f infrastructure/argocd/apps/my-app.yaml
```

3. **Watch deployment:**
```bash
kubectl get application -n argocd
kubectl describe application -n argocd my-app
```

### Currently Deployed Applications

#### homebrain-api
- **Manifest:** `apps/homebrain-api.yaml`
- **Source Path:** `k8s/backend`
- **Namespace:** `homebrain`
- **Target Node:** k3s-worker (ARM64)
- **Sync Policy:** Automated (prune + selfHeal)
- **Status:** ✅ Healthy and Synced

**View status:**
```bash
kubectl get application -n argocd homebrain-api
kubectl get pods -n homebrain -o wide
```

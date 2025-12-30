# ArgoCD Installation

## Current Status

ArgoCD is installed and accessible via Tailscale, but **not actively managing applications**. All deployments are handled manually via `kubectl apply`.

**Tailscale Access**: https://argocd-1.dove-komodo.ts.net

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

Applications are managed via manifests in `apps/` directory. Each application is deployed as an ArgoCD Application CRD.

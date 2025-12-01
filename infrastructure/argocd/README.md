# ArgoCD Installation

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

## Configuration

See `helm-values.yaml` for the custom configuration:
- All components pinned to `k3s-master` node
- HA mode disabled (single-node deployment for home lab)

## Access

### CLI Access

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login via CLI
argocd login localhost:8080 --username admin
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

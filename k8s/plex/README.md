# Plex Media Server on K3s

Plex Media Server deployment with GPU acceleration and dual access:
- 🔒 Private: `plex.dove-komodo.ts.net` (Tailscale)
- 🌐 Public: `plex.kanokgan.com` (Cloudflare Tunnel)

## Prerequisites

1. **K3s cluster with NVIDIA GPU** (see [RB-001: Infrastructure](../../docs/runbooks/01-infrastructure.md))
2. **Tailscale auth key** from https://login.tailscale.com/admin/settings/keys
   - Enable "Reusable" and "Ephemeral"
3. **Plex claim token** from https://www.plex.tv/claim/ (valid for 4 minutes)
4. **NFS shares mounted** on k3s-master:
   - `/volume1/Media` → `/mnt/Media`
   - `/volume1/Nrop` → `/mnt/Nrop`

## Deployment Steps

### 1. Create Namespace and RBAC

```bash
kubectl apply -f k8s/plex/namespace.yaml
kubectl apply -f k8s/plex/rbac.yaml
```

### 2. Create Tailscale Secret

Get your Tailscale auth key and create the secret:

```bash
kubectl create secret generic tailscale-auth \
  --namespace plex \
  --from-literal=TS_AUTHKEY="tskey-auth-YOUR_KEY_HERE"
```

### 3. Update Plex Claim Token

Get a claim token from https://www.plex.tv/claim/ (valid for 4 minutes) and update the deployment:

```bash
# Edit deployment.yaml and replace:
# PLEX_CLAIM: "claim-PLACEHOLDER_REPLACE_WITH_TOKEN_FROM_PLEX_TV"
# with your actual token:
# PLEX_CLAIM: "claim-XXXXXXXXXXXXX"

# Or use sed:
CLAIM_TOKEN="claim-YOUR_TOKEN_HERE"
sed -i '' "s/claim-PLACEHOLDER_REPLACE_WITH_TOKEN_FROM_PLEX_TV/$CLAIM_TOKEN/" k8s/plex/deployment.yaml
```

### 4. Deploy Plex

```bash
kubectl apply -f k8s/plex/pvc.yaml
kubectl apply -f k8s/plex/tailscale-config.yaml
kubectl apply -f k8s/plex/deployment.yaml
kubectl apply -f k8s/plex/service.yaml
kubectl apply -f k8s/plex/network-policy.yaml
```

### 5. Wait for Deployment

```bash
kubectl wait --for=condition=ready pod -l app=plex -n plex --timeout=300s
kubectl logs -n plex -l app=plex -c plex --tail=50
```

### 6. Configure Cloudflare Tunnel

Go to Cloudflare Zero Trust Dashboard → Tunnels → `home-brain`:

1. Click **Public Hostname** tab
2. Click **Add a public hostname**
3. Configure:
   - **Subdomain**: `plex`
   - **Domain**: `kanokgan.com`
   - **Service Type**: `HTTP`
   - **URL**: `plex.plex.svc.cluster.local:32400`
4. Click **Save hostname**

### 7. Test Access

```bash
# Via Tailscale (from Tailscale network)
curl -k https://plex.dove-komodo.ts.net

# Via Cloudflare (public)
curl https://plex.kanokgan.com
```

Open in browser:
- https://plex.dove-komodo.ts.net
- https://plex.kanokgan.com

## Post-Deployment

### Add Media Libraries

1. Log into Plex web UI
2. Go to **Settings** → **Manage** → **Libraries**
3. Click **Add Library**
4. Add folders:
   - `/media` (your main media)
   - `/nrop` (additional content)

### Verify GPU Transcoding

1. Play a video that requires transcoding
2. Check logs:
   ```bash
   kubectl logs -n plex -l app=plex -c plex | grep -i nvenc
   ```
   Should show NVIDIA hardware transcoding being used.

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n plex
kubectl describe pod -n plex -l app=plex
```

### Check Logs
```bash
# Plex container
kubectl logs -n plex -l app=plex -c plex --tail=100

# Tailscale sidecar
kubectl logs -n plex -l app=plex -c tailscale --tail=50
```

### Check GPU Access
```bash
kubectl exec -n plex -c plex $(kubectl get pod -n plex -l app=plex -o name) -- nvidia-smi
```

### Check NFS Mounts
```bash
kubectl exec -n plex -c plex $(kubectl get pod -n plex -l app=plex -o name) -- ls -la /media
kubectl exec -n plex -c plex $(kubectl get pod -n plex -l app=plex -o name) -- ls -la /nrop
```

### Tailscale Not Working
```bash
# Check if Tailscale is authenticated
kubectl logs -n plex -l app=plex -c tailscale | grep -i "logged in"

# Regenerate auth key if expired
kubectl delete secret tailscale-auth -n plex
# Create new secret with fresh key
```

## Updating Plex

```bash
# Recreate deployment to pull latest image
kubectl rollout restart deployment/plex -n plex

# Watch progress
kubectl rollout status deployment/plex -n plex
```

## Storage

- **Config**: 20Gi on local-path (metadata, database)
- **Transcode**: 100Gi on local-path (temporary transcoding files)
- **Media**: NFS read-only mounts from NAS

## GPU Sharing Note

This deployment uses the same GPU as Jellyfin. Only run one service at a time, or adjust GPU resource requests if your GPU supports time-slicing.

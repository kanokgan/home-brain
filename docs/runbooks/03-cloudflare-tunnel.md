# 🌐 Runbook: Cloudflare Tunnel Setup

| Metadata | Details |
| :--- | :--- |
| **ID** | RB-003 |
| **Status** | Active |
| **Maintainer** | @Kanokgan |
| **Last Updated** | 2025-12-01 |
| **Objective** | Configure Cloudflare Tunnel for secure external access to ArgoCD |

---

## 🎯 Overview

Cloudflare Tunnel creates a secure, outbound-only connection from your home cluster to Cloudflare's edge network. No inbound ports need to be opened on your router.

**Benefits:**
- ✅ No port forwarding required
- ✅ Automatic SSL/TLS termination
- ✅ DDoS protection via Cloudflare
- ✅ Optional authentication via Cloudflare Access
- ✅ High availability with multiple replicas

---

## 📋 Prerequisites

1. Cloudflare account with `kanokgan.com` domain configured
2. K3s cluster running (from RB-001)
3. ArgoCD deployed in `argocd` namespace
4. `kubectl` configured with cluster access

---

## 🚀 Step 1: Create Cloudflare Tunnel

### 1.1 Via Cloudflare Dashboard

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Click **Create a tunnel**
4. Select **Cloudflared** tunnel type
5. Name: `homebrain-k3s`
6. Click **Save tunnel**
7. **IMPORTANT**: Copy the tunnel token shown (you'll need this)

### 1.2 Get Tunnel Details

After creation, note down:
- **Tunnel ID**: Found in the tunnel overview (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- **Account ID**: Found in Cloudflare dashboard URL or Account settings
- **Tunnel Token**: The token shown during creation

---

## 🔐 Step 2: Create Kubernetes Secret

**⚠️ SECURITY**: Never commit these credentials to Git!

```bash
# Set your credentials as environment variables
export TUNNEL_TOKEN="your-tunnel-token-here"
export TUNNEL_ID="your-tunnel-id-here"
export ACCOUNT_ID="your-account-id-here"

# Create namespace
kubectl create namespace cloudflare

# Create secret with tunnel token (easiest method)
kubectl create secret generic cloudflare-tunnel-credentials \
  --namespace cloudflare \
  --from-literal=tunnel-token="$TUNNEL_TOKEN"

# Verify secret was created
kubectl get secret cloudflare-tunnel-credentials -n cloudflare
```

---

## ⚙️ Step 3: Update Configuration

Update the tunnel ID in the ConfigMap:

```bash
cd /Users/kanokgan/Developer/personal/home-brain

# Edit the configmap
kubectl apply -f infrastructure/cloudflare/namespace.yaml

# Create ConfigMap with your tunnel ID
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflare
data:
  config.yaml: |
    tunnel: $TUNNEL_ID
    credentials-file: /etc/cloudflared/credentials/tunnel-token
    metrics: 0.0.0.0:2000
    no-autoupdate: true
    
    ingress:
      # ArgoCD
      - hostname: argocd.kanokgan.com
        service: https://argocd-server.argocd.svc.cluster.local:443
        originRequest:
          noTLSVerify: true
      
      # Catch-all rule (required)
      - service: http_status:404
EOF
```

---

## 🚢 Step 4: Deploy Cloudflared

```bash
# Deploy the tunnel daemon
kubectl apply -f infrastructure/cloudflare/deployment.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l app=cloudflared \
  -n cloudflare \
  --timeout=60s

# Check logs
kubectl logs -n cloudflare -l app=cloudflared --tail=50
```

Expected log output:
```
INF Starting tunnel tunnelID=xxxxx
INF Connection registered connIndex=0
INF Connection registered connIndex=1
```

---

## 🌍 Step 5: Configure DNS in Cloudflare

### Via Cloudflare Dashboard (Recommended)

1. Go to **Cloudflare Dashboard** → Select `kanokgan.com`
2. Go to **DNS** → **Records**
3. Click **Add record**
4. Configure:
   - **Type**: `CNAME`
   - **Name**: `argocd`
   - **Target**: `<TUNNEL_ID>.cfargotunnel.com`
   - **Proxy status**: Proxied (orange cloud)
   - **TTL**: Auto
5. Click **Save**

### Via CLI (Alternative)

```bash
# Using Cloudflare API (requires API token)
curl -X POST "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/dns_records" \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "CNAME",
    "name": "argocd",
    "content": "'$TUNNEL_ID'.cfargotunnel.com",
    "proxied": true
  }'
```

---

## ✅ Step 6: Verify Access

```bash
# Wait for DNS propagation (usually < 1 minute)
sleep 60

# Test DNS resolution
dig argocd.kanokgan.com

# Test HTTPS access
curl -I https://argocd.kanokgan.com

# Expected: HTTP/2 200 or 302 redirect
```

Access ArgoCD in your browser:
```
https://argocd.kanokgan.com
```

**Login credentials:**
- Username: `admin`
- Password: Get from kubectl:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  ```

---

## 🔒 Step 7: Enable Cloudflare Access (Optional but Recommended)

Add an authentication layer before ArgoCD:

### 7.1 Create Access Application

1. Go to **Zero Trust Dashboard** → **Access** → **Applications**
2. Click **Add an application** → **Self-hosted**
3. Configure:
   - **Application name**: `HomeBrain ArgoCD`
   - **Session Duration**: 24 hours
   - **Application domain**: `argocd.kanokgan.com`
4. Click **Next**

### 7.2 Add Access Policy

1. **Policy name**: `Allow My Email`
2. **Action**: Allow
3. **Configure rules**:
   - **Selector**: `Emails`
   - **Value**: `your-email@gmail.com`
4. Click **Next** → **Add application**

Now accessing `argocd.kanokgan.com` will require authentication through Cloudflare first!

---

## 🧪 Troubleshooting

### Issue 1: Tunnel Not Connecting

**Symptoms**: Logs show "failed to connect to edge"

```bash
# Check tunnel credentials
kubectl get secret cloudflare-tunnel-credentials -n cloudflare -o yaml

# Check pod logs
kubectl logs -n cloudflare -l app=cloudflared --tail=100

# Verify tunnel exists in Cloudflare dashboard
# Ensure tunnel token is correct
```

### Issue 2: 502 Bad Gateway

**Symptoms**: Browser shows Cloudflare 502 error

```bash
# Check ArgoCD is running
kubectl get pods -n argocd

# Check service exists
kubectl get svc argocd-server -n argocd

# Test connectivity from cloudflared pod
kubectl exec -n cloudflare deploy/cloudflared -- \
  curl -k https://argocd-server.argocd.svc.cluster.local:443
```

### Issue 3: DNS Not Resolving

**Symptoms**: `argocd.kanokgan.com` doesn't resolve

```bash
# Check DNS record in Cloudflare
# Ensure CNAME points to <TUNNEL_ID>.cfargotunnel.com
# Verify proxy is enabled (orange cloud)

# Test DNS
nslookup argocd.kanokgan.com 1.1.1.1
```

### Issue 4: Certificate Errors

**Symptoms**: SSL/TLS warnings in browser

**Solution**: This should not happen with Cloudflare proxy enabled. If it does:
- Verify proxy status is "Proxied" in Cloudflare DNS
- Check SSL/TLS encryption mode is "Full" or "Full (strict)" in Cloudflare

---

## 🎯 Success Criteria

✅ You should be able to:
1. Access `https://argocd.kanokgan.com` from any network
2. See valid SSL certificate (issued by Cloudflare)
3. Login to ArgoCD web interface
4. No port forwarding needed

---

## 📝 Notes

- The tunnel runs as 2 replicas for high availability
- If one pod crashes, the other maintains connectivity
- Tunnel automatically reconnects if connection drops
- Metrics available at `localhost:2000/metrics` within pods
- To add more services, update the ConfigMap ingress rules

---

## 🔄 Adding More Services

To expose additional services (e.g., Grafana, Traefik):

1. Update `infrastructure/cloudflare/configmap.yaml`
2. Add new ingress rule before the catch-all:
   ```yaml
   - hostname: grafana.kanokgan.com
     service: http://grafana.monitoring.svc.cluster.local:80
   ```
3. Apply changes: `kubectl apply -f infrastructure/cloudflare/configmap.yaml`
4. Restart cloudflared: `kubectl rollout restart deployment/cloudflared -n cloudflare`
5. Add DNS CNAME record in Cloudflare for the new hostname

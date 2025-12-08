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

## ⚙️ Step 3: Apply Kubernetes Namespace

**IMPORTANT:** When using token-based tunnels, routing configuration is managed through the Cloudflare Dashboard, not ConfigMaps. The ConfigMap in this repo is kept for reference only.

```bash
cd /Users/kanokgan/Developer/personal/home-brain

# Apply namespace
kubectl apply -f infrastructure/cloudflare/namespace.yaml
```

**Note:** Skip ConfigMap creation - it's not used with token-based authentication.

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

## 🌍 Step 5: Configure Tunnel Route & DNS

### 5.1 Configure Public Hostname (Cloudflare Dashboard)

**This is where routing configuration actually lives for token-based tunnels:**

1. Go to **Zero Trust Dashboard** → **Networks** → **Tunnels**
2. Click on your `homebrain-k3s` tunnel
3. Go to **Public Hostname** tab
4. Click **Add a public hostname**
5. Configure:
   - **Subdomain**: `argocd`
   - **Domain**: `kanokgan.com`
   - **Service Type**: `HTTP`
   - **URL**: `argocd-server.argocd.svc.cluster.local:80`
6. Click **Save hostname**

**Important:** 
- Use `HTTP` (not HTTPS) if ArgoCD is running in insecure mode (`server.insecure=true`)
- Use `HTTPS` with "No TLS Verify" enabled if ArgoCD uses self-signed certificates
- The DNS record is created automatically when you add a public hostname

### 5.2 Verify DNS (Automatic)

Cloudflare automatically creates the DNS record. Verify:

1. Go to **Cloudflare Dashboard** → Select `kanokgan.com`
2. Go to **DNS** → **Records**
3. You should see:
   - **Type**: `CNAME`
   - **Name**: `argocd`
   - **Target**: `<TUNNEL_ID>.cfargotunnel.com`
   - **Proxy status**: Proxied (orange cloud)

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

## 🔧 Step 7: Configure ArgoCD for Cloudflare Access (Optional)

If you want to use Cloudflare Access (Zero Trust authentication), ArgoCD must run in insecure mode since Cloudflare handles TLS termination.

### 7.1 Enable ArgoCD Insecure Mode

```bash
# Configure ArgoCD to run without TLS
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'

# Restart ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd

# Wait for restart
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s
```

**Important:** After enabling insecure mode:
1. ArgoCD listens on HTTP port 80 (not HTTPS port 443)
2. Update the tunnel route in Cloudflare Dashboard:
   - Go to Zero Trust → Networks → Tunnels → homebrain-k3s → Public Hostname
   - Edit `argocd.kanokgan.com` route
   - Change Service Type to `HTTP`
   - Change URL to `argocd-server.argocd.svc.cluster.local:80`
   - Remove "No TLS Verify" (not needed for HTTP)
   - Save

---

## 🔒 Step 8: Enable Cloudflare Access (Optional but Recommended)

Add an authentication layer before ArgoCD:

### 8.1 Create Access Application

1. Go to **Zero Trust Dashboard** → **Access** → **Applications**
2. Click **Add an application** → **Self-hosted**
3. Configure:
   - **Application name**: `HomeBrain ArgoCD`
   - **Session Duration**: 24 hours
   - **Application domain**: `argocd.kanokgan.com`
4. Click **Next**

### 8.2 Add Access Policy

1. **Policy name**: `Allow My Email`
2. **Action**: Allow
3. **Configure rules**:
   - **Selector**: `Emails`
   - **Value**: `your-email@gmail.com`
4. Click **Next** → **Add application**

Now accessing `argocd.kanokgan.com` will require authentication through Cloudflare first!

**Note:** With Cloudflare Access enabled, users see a login page before reaching ArgoCD. This provides an additional security layer on top of ArgoCD's own authentication.

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

### Issue 2: 502 Bad Gateway or Connection Reset

**Symptoms**: Browser shows Cloudflare 502 error or "connection reset by peer"

**Common Cause**: Protocol mismatch - tunnel configured for HTTPS but ArgoCD is using HTTP (or vice versa)

```bash
# Check if ArgoCD is in insecure mode
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep insecure

# If server.insecure=true, ArgoCD uses HTTP on port 80
# Test HTTP connection
kubectl run test-http --rm -i --restart=Never --image=curlimages/curl -- \
  curl -I http://argocd-server.argocd.svc.cluster.local:80

# If server.insecure=false or not set, ArgoCD uses HTTPS on port 443
# Test HTTPS connection
kubectl run test-https --rm -i --restart=Never --image=curlimages/curl -- \
  curl -k -I https://argocd-server.argocd.svc.cluster.local:443
```

**Solution**: Update tunnel route in Cloudflare Dashboard to match ArgoCD's protocol:
- **Insecure mode** → Service Type: `HTTP`, URL: `argocd-server.argocd.svc.cluster.local:80`
- **Secure mode** → Service Type: `HTTPS`, URL: `argocd-server.argocd.svc.cluster.local:443` (enable "No TLS Verify")

### Issue 3: DNS Not Resolving

**Symptoms**: `argocd.kanokgan.com` doesn't resolve

```bash
# Check DNS record in Cloudflare
# Ensure CNAME points to <TUNNEL_ID>.cfargotunnel.com
# Verify proxy is enabled (orange cloud)

# Test DNS
nslookup argocd.kanokgan.com 1.1.1.1
```

### Issue 4: Pods Crash Loop - Liveness Probe Failed

**Symptoms**: `kubectl get pods -n cloudflare` shows `CrashLoopBackOff`, events show "Liveness probe failed: connection refused"

**Root Cause**: The metrics server listens on `127.0.0.1:2000` (localhost only), but the default httpGet probe tries to access it via the pod IP.

**Solution**: Already fixed in deployment.yaml - uses `exec` command to check localhost:
```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - 'wget -q -O /dev/null http://127.0.0.1:2000/ready || exit 1'
```

If you see this issue, ensure you're using the latest deployment.yaml from the repo.

### Issue 5: Certificate Errors

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

**With token-based tunnels**, all routing is managed through the Cloudflare Dashboard:

1. Go to **Zero Trust Dashboard** → **Networks** → **Tunnels**
2. Click on your `homebrain-k3s` tunnel
3. Go to **Public Hostname** tab
4. Click **Add a public hostname**
5. Configure the new service:
   - **Subdomain**: `grafana` (or your service name)
   - **Domain**: `kanokgan.com`
   - **Service Type**: `HTTP` or `HTTPS`
   - **URL**: `service-name.namespace.svc.cluster.local:port`
6. Click **Save hostname**

**Note:** The ConfigMap in this repo is NOT used with token-based deployment. All routing configuration lives in Cloudflare's dashboard. DNS records are created automatically.

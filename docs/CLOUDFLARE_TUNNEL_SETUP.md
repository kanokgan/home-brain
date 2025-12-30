# Cloudflare Tunnel Setup Guide for Immich

Quick reference for setting up Cloudflare Tunnel to access Immich at `immich.kanokgan.com`.

## Prerequisites

- ✅ Immich deployed in K3s (see [RB-003: Immich Deployment](docs/runbooks/03-immich-deployment.md))
- ✅ Cloudflare account with `kanokgan.com` domain
- ✅ Cloudflare Zero Trust (Free tier available)

## Step 1: Create Cloudflare Tunnel (Dashboard)

1. Go to https://one.dash.cloudflare.com/
2. Navigate to **Networks** → **Tunnels**
3. Click **Create a tunnel**
4. Select **Cloudflared** tunnel type
5. Name it: `home-brain`
6. Click **Save tunnel**
7. **Copy the tunnel token** (starts with `eyJ...`)

## Step 2: Add Token to K3s

```bash
# Create the cloudflare namespace
kubectl create namespace cloudflare

# Create secret with your tunnel token
kubectl create secret generic cloudflare-tunnel-credentials \
  --namespace cloudflare \
  --from-literal=tunnel-token="<PASTE_YOUR_TOKEN_HERE>"

# Verify
kubectl get secret cloudflare-tunnel-credentials -n cloudflare
```

## Step 3: Deploy Cloudflared Pod

```bash
cd /Users/kanokgan/Developer/personal/home-brain

# Deploy
kubectl apply -f infrastructure/cloudflare/namespace.yaml
kubectl apply -f infrastructure/cloudflare/deployment.yaml

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app=cloudflared -n cloudflare --timeout=60s

# Check logs
kubectl logs -n cloudflare -l app=cloudflared --tail=20
```

You should see: `Connection registered connIndex=0` and `Connection registered connIndex=1`

## Step 4: Configure Routes in Cloudflare Dashboard

1. Go back to **Tunnels** in Cloudflare Dashboard
2. Click on your `home-brain` tunnel
3. Go to **Public Hostname** tab
4. Click **Add a public hostname**

### For Immich:
- **Subdomain**: `immich`
- **Domain**: `kanokgan.com`
- **Service Type**: `HTTP`
- **URL**: `immich-server.immich.svc.cluster.local:80`
- Click **Save hostname**

DNS record will be created automatically!

## Step 5: Test Access

```bash
# Wait for DNS propagation
sleep 60

# Test it
curl -I https://immich.kanokgan.com

# Should return: HTTP/2 200 or 301
```

## Step 6: Access in Browser

Open https://immich.kanokgan.com in your browser!

You now have:
- **Private access**: https://immich.dove-komodo.ts.net (Tailscale)
- **Public access**: https://immich.kanokgan.com (Cloudflare)
- **Local access**: http://immich.home.local (LAN)

## Troubleshooting

### Tunnel not connecting
```bash
# Check pod status
kubectl get pods -n cloudflare -w

# Check logs
kubectl logs -n cloudflare deployment/cloudflared --tail=50
```

### DNS not resolving
```bash
# Verify DNS record in Cloudflare dashboard
dig immich.kanokgan.com @1.1.1.1
```

### Getting 502 errors
Check that Immich is actually running:
```bash
kubectl get pods -n immich | grep immich-server
kubectl exec -n immich deployment/immich-server -c immich-server -- curl -I http://localhost:2283
```

## Next Steps

- Add other services to the tunnel (ArgoCD, monitoring, etc.)
- Enable Cloudflare Access for additional authentication layer
- Configure Cloudflare WAF rules for additional security

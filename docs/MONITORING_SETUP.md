# Monitoring Stack Setup (Loki + Grafana + Promtail)

## Overview

Centralized logging stack for Kubernetes:
- **Loki**: Log aggregation (stores on NAS)
- **Promtail**: Log collection agent (runs on each node)
- **Grafana**: Visualization UI (accessible via Tailscale)

## Architecture

- **Loki Storage**: NAS at `/mnt/loki-logs` (HomeBrain/loki-logs)
- **Grafana Storage**: Local SSD PVC (persistent admin settings)
- **Access**: Tailscale at `https://grafana.dove-komodo.ts.net`

## Prerequisites

1. K3s cluster running
2. NAS mounted on k3s-master at `/mnt/loki-logs`
3. Tailscale auth key configured

## Step 1: Create NAS Mount for Loki Logs

SSH to k3s-master:

```bash
ssh ubuntu@192.168.0.206

# Create mount point
sudo mkdir -p /mnt/loki-logs

# Add to /etc/fstab
sudo nano /etc/fstab

# Add this line:
//100.77.209.53/HomeBrain/loki-logs /mnt/loki-logs cifs credentials=/root/.smbcredentials,uid=472,gid=472,file_mode=0777,dir_mode=0777,_netdev 0 0

# Mount
sudo mount /mnt/loki-logs

# Create Loki directories
sudo mkdir -p /mnt/loki-logs/{wal,chunks,boltdb-shipper-active,compactor,boltdb-cache,index_}
Configure Tailscale Auth Key

Create a reusable auth key at https://login.tailscale.com/admin/settings/keys

```bash
# Update the secret with your auth key
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY="tskey-auth-YOUR-KEY-HERE" \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -
```

## Step 3: 
# Verify
df -h /mnt/loki-logsrbac.yaml
kubectl apply -f k8s/monitoring/tailscale-config.yaml

# Deploy Loki
kubectl apply -f k8s/monitoring/loki-config.yaml
kubectl apply -f k8s/monitoring/loki.yaml
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=120s

# Deploy Promtail
kubectl apply -f k8s/monitoring/promtail-config.yaml
kubectl apply -f k8s/monitoring/promtail.yaml

# Deploy Grafana
kubectl apply -f k8s/monitoring/grafana.yaml
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=12
 READY   STATUS    RESTARTS   AGE
grafana-xxxxx-xxxxx        2/2     Running   0          2m
loki-0                     1/1     Running   0          3m
promtail-xxxxx             1/1     Running   0          2m
```

## Step 4: Access Grafana

### Primary Method: Tailscale

Access Grafana at: **https://grafana.dove-komodo.ts.net**

### Option B: LoadBalancer (Persistent)
If using LoadBalancer:
```bash
# Get external IP
kubectl get svc -n monitoring grafana
# Access at that IP
```

### Add to Hosts (Optional)
```bash
# On your Mac, add to /etc/hosts:
192.168.0.206  grafana.home.local

# Then access at: http://grafana.home.local
```

### Login
- **Username**: `admin`
- **Password**: `admin` (change after first login!)
  
Or retrieve from secret:
```bash
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

## Step 4: View Logs in Grafana

1. Go to **Explore** (left sidebar)
2. Select **Loki** datasource
3. Use LogQL queries:

### Example Queries

**All logs from immich namespace:**
```logql
{namespace="immich"}
**Login Credentials:**
- **Username**: `admin`
- **Password**: `admin` (persists across restarts via PVC)

### Alternative: Port Forward (Local Access)
{namespace="immich", container="immich-server"}
```

**Search for errors:**
```logql
{namespace="immich"} |= "error"
```
port-forward -n monitoring svc/grafana 3000:80
# Access at: http://localhost:3000
```

## Step 5e="immich", app="immich-machine-learning"} |= "CUDA"
```

**Tailscale sidecar logs:**
```logql
{namespace="immich", container="tailscale"}
```
all namespaces:**
```logql
{namespace=~".+"}
```

**Immich logs:**
```logql
{namespace="immich"}
```

**Immich server container only:**
```logql
{namespac Storage**: boltdb-shipper on NAS
- **Chunks**: Stored on NAS at `/mnt/loki-logs/chunks`
- **WAL**: Write-ahead log at `/mnt/loki-logs/wal`
- **Retention**: Indefinite (no auto-deletion)
- **Compression**: ~10:1 ratio (very efficient)

### Grafana Configuration
- **Database**: SQLite on local SSD PVC (10Gi)
- **Settings**: Persist across restarts
- **Dashboards**: Persist across restarts
- **Plugins**: grafana-piechart-panel

Clear old Loki data:
```bash
ssh ubuntu@192.168.0.206
sudo rm -rf /mnt/loki-logs/chunks/*
sudo rm -rf /mnt/loki-logs/boltdb-shipper-active/*
sudo rm -rf /mnt/loki-logs/index_/*

# Restart Loki to reinitialize
kubectl delete pod -n monitoring loki-0
{namespace="immich", container="tailscale"}
```

**Cloudflare tunneStack

```bash
# Check all pods
kubectl get pods -n monitoring

# Check Loki health
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/ready

# Check available log labels
kubectl exec -n monitoring loki-0 -- wget -qO- 'http://localhost:3100/loki/api/v1/label'

# Check namespaces in Loki
kubectl exec -n monitoring loki-0 -- wget -qO- 'http://localhost:3100/loki/api/v1/label/namespace/values'

# Check Promtail logs
```bash
# Check pod status
kubectl describe pod -n monitoring loki-0

# Check NAS mount
ssh ubuntu@192.168.0.206
df -h /mnt/loki-logs
ls -la /mnt/loki-logs

# Remount if needed
sudo mount /mnt/loki-logs

# Check Loki logs
kubectl logs -n monitoring loki-0 --tail=50
```

### Promtail not collecting logs
```bash
# Check Promtail status
kubectl get pods -n monitoring -l app=promtail

# Check Promtail logs for "Adding target" messages
kubectl logs -n monitoring -l app=promtail --tail=50

# Verify Loki is reachable
kubectl exec -n monitoring -l app=promtail -- wget -qO- http://loki:3100/ready
```

### Grafana can't reach Loki
```bash
# Test from Grafana pod
kubectl exec -n monitoring -l app=grafana -c grafana -- wget -qO- http://loki:3100/ready

# Check Loki service
kubectl get svc -n monitoring loki
kubectl get endpoints -n monitoring loki
```

### No logs in Grafana
1. Wait 1-2 minutes for initial log ingestion
2. Use correct query: `{namespace="immich"}` (not `{job="kubernetes-pods"}`)
3. Check time range (use "Last 15 minutes")
4. Verify Promtail is tailing: `kubectl logs -n monitoring -l app=promtail | grep "tail routine: started"`
5. Check Loki has data: `kubectl exec -n monitoring loki-0 -- wget -qO- 'http://localhost:3100/loki/api/v1/label/namespace/values'`

### Grafana Tailscale not working
```bash
# CKey Features

- ✅ Centralized logging for all K8s pods
- ✅ Loki data stored on NAS (persistent, cost-effective)
- ✅ Grafana settings stored on local SSD PVC (fast, persistent)
- ✅ Remote access via Tailscale (secure, no port forwarding)
- ✅ LogQL queries for powerful log filtering
- ✅ Dashboard auto-provisioning support
- ✅ Compressed storage (~10:1 ratio)

## Next Steps

- Create custom Grafana dashboards
- Set up log-based alerts
- Add Prometheus for metrics
- Configure log retention policies
- Integrate with alerting systems (Slack, email)
kubectl exec -n monitoring -l app=grafana -c tailscale -- tailscale status
```

### Grafana admin password reset on restart
This should not happen with PVC storage. If it does:
```bash
# Check PVC is bound
kubectl get pvc -n monitoring grafana-pvc

# Check pod is using PVC
kubectl describe pod -n monitoring -l app=grafana | grep -A 5 "Volumes:"

# Verify Loki is reachable from Promtail
kubectl exec -n monitoring -l app=promtail -- curl -s http://loki:3100/ready
```

### Grafana can't reach Loki
```bash
# Check network connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n monitoring -- \
  curl http://loki:3100/ready

# Check Loki service
kubectl get svc -n monitoring loki
kubectl get endpoints loki -n monitoring
```

### No logs appearing in Grafana
1. Wait 1-2 minutes for logs to be shipped
2. Try a broader query: `{namespace="immich"}`
3. Check Promtail logs for errors
4. Verify Loki storage directory has files:
   ```bash
   ssh ubuntu@192.168.0.206
   ls -la /mnt/loki-logs/
   ```

## Next Steps

- Add Loki datasource to Immich alerts
- Create Grafana dashboards for visualization
- Set up Prometheus for metrics + Loki for logs
- Configure Grafana alerts
- Access Grafana externally via Cloudflare tunnel or Tailscale

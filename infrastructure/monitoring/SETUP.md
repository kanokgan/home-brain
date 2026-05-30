# Kube-Prometheus-Stack Setup Guide

Complete monitoring solution with Prometheus, Grafana, AlertManager, and more.

**Access:** https://monitoring.dove-komodo.ts.net (via Tailscale)

## What You Get

- ✅ **Prometheus** - Metrics collection with 30-day retention
- ✅ **Grafana** - 50+ pre-built dashboards
- ✅ **AlertManager** - Alert routing and notifications
- ✅ **node-exporter** - Hardware metrics (CPU, RAM, disk, network)
- ✅ **kube-state-metrics** - Kubernetes object metrics
- ✅ **Prometheus Operator** - Easy metric configuration
- ✅ **Pre-configured alerts** - High CPU, disk full, pod crashes, etc.

## Prerequisites

1. K3s cluster running with kubectl access
2. Helm 3 installed
3. Tailscale auth key (reusable recommended)

## Quick Install

```bash
cd infrastructure/monitoring

# 1. Create Tailscale auth key secret
# Get your auth key from: https://login.tailscale.com/admin/settings/keys
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY='tskey-auth-YOUR-KEY-HERE' \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# 2. Run installation script
chmod +x install.sh
./install.sh
```

That's it! Wait 3-5 minutes for all components to start.

## Manual Installation

If you prefer step-by-step:

```bash
# 1. Create namespace
kubectl create namespace monitoring

# 2. Create Tailscale secret
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY='tskey-auth-YOUR-KEY-HERE' \
  -n monitoring

# 3. Apply Tailscale configuration
kubectl apply -f tailscale-config.yaml

# 4. Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 5. Install kube-prometheus-stack
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kube-prometheus-values.yaml \
  --wait

# 6. Check status
kubectl get pods -n monitoring
```

## Access Grafana

1. Go to https://monitoring.dove-komodo.ts.net (via Tailscale network)
2. Login: `admin` / `admin`
3. Change password immediately
4. Explore dashboards under "Dashboards" menu

## Recommended Dashboards

Navigate to **Dashboards** in Grafana to find:

1. **Node Exporter Full** - Complete node metrics (CPU, RAM, disk, network)
2. **Kubernetes / Compute Resources / Cluster** - Cluster-wide resource usage
3. **Kubernetes / Compute Resources / Namespace (Pods)** - Per-pod metrics
4. **Kubernetes / Networking / Cluster** - Network traffic
5. **Prometheus / Overview** - Prometheus health metrics

## Adding GPU Monitoring (Optional)

If you have NVIDIA GPUs on your k3s-worker-gpu node:

```bash
# Install DCGM exporter for GPU metrics
kubectl apply -f https://nvidia.github.io/dcgm-exporter/examples/dcgm-exporter.yaml

# Update kube-prometheus-values.yaml to add GPU scrape config:
# prometheus:
#   prometheusSpec:
#     additionalScrapeConfigs:
#       - job_name: 'nvidia-dcgm'
#         static_configs:
#           - targets: ['dcgm-exporter.kube-system.svc:9400']

# Upgrade Helm release
helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kube-prometheus-values.yaml
```

## Integrating Loki for Logs

If you want to add your existing Loki instance:

```bash
# Deploy Loki (if not already deployed)
kubectl apply -f ../../k8s/monitoring/loki-config.yaml
kubectl apply -f ../../k8s/monitoring/loki.yaml
kubectl apply -f ../../k8s/monitoring/promtail-config.yaml
kubectl apply -f ../../k8s/monitoring/promtail.yaml

# Loki is already configured as a datasource in kube-prometheus-values.yaml
# Just restart Grafana to pick it up:
kubectl rollout restart deployment kube-prometheus-grafana -n monitoring
```

## Setting Up Alerts

Edit `kube-prometheus-values.yaml` and add notification receivers:

### Telegram
```yaml
alertmanager:
  config:
    receivers:
      - name: 'telegram'
        telegram_configs:
          - bot_token: 'YOUR_BOT_TOKEN'
          - chat_id: YOUR_CHAT_ID
            message: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

### Discord Webhook
```yaml
alertmanager:
  config:
    receivers:
      - name: 'discord'
        webhook_configs:
          - url: 'YOUR_DISCORD_WEBHOOK_URL'
            send_resolved: true
```

Then upgrade:
```bash
helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kube-prometheus-values.yaml
```

## Troubleshooting

### Grafana not accessible via Tailscale
```bash
# Check Grafana pod logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c ts-sidecar

# Check Tailscale status
kubectl exec -n monitoring -it deployment/kube-prometheus-grafana -c ts-sidecar -- tailscale status

# Verify serve config
kubectl get cm tailscale-serve-config -n monitoring -o yaml
```

### Prometheus storage full
```bash
# Check PVC size
kubectl get pvc -n monitoring

# Increase retention in kube-prometheus-values.yaml:
# prometheus:
#   prometheusSpec:
#     retention: 15d  # Reduce from 30d
#     retentionSize: "18GB"

helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kube-prometheus-values.yaml
```

### Check all components
```bash
kubectl get all -n monitoring
kubectl get pvc -n monitoring
```

## Uninstall

```bash
helm uninstall kube-prometheus -n monitoring
kubectl delete namespace monitoring
```

## Storage Requirements

- **Prometheus**: 20GB (30 days of metrics)
- **Grafana**: 10GB (dashboards and settings)
- **AlertManager**: 5GB (alert history)
- **Tailscale**: 1GB (state)

**Total**: ~36GB local storage

## Resource Usage

Expected resource consumption:
- **CPU**: ~300-500m total
- **Memory**: ~1.5-2.5GB total

Perfect for homelab environments!

## Next Steps

1. ✅ Access Grafana and change admin password
2. ✅ Explore pre-built dashboards
3. ✅ Set up AlertManager notifications (Telegram/Discord)
4. ✅ Add GPU monitoring if you have NVIDIA GPUs
5. ✅ Integrate Loki for log aggregation
6. ✅ Create custom dashboards for your services (Immich, Jellyfin, etc.)

## Resources

- [Kube-Prometheus-Stack Documentation](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Prometheus Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [AlertManager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

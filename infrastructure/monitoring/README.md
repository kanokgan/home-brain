# Monitoring & Observability

## Stack

- **Prometheus** - Metrics collection
- **Grafana** - Visualization dashboards
- **Loki** - Log aggregation
- **AlertManager** - Alert routing (optional)

## Setup Tasks

- [ ] Install kube-prometheus-stack
- [ ] Configure ServiceMonitors
- [ ] Setup Grafana dashboards
- [ ] Configure Loki for log collection
- [ ] Add custom metrics for Golang API

## Key Metrics to Track

- Node resource usage (CPU, Memory, Disk)
- Pod health and restarts
- GPU utilization (k3s-worker-gpu)
- API response times
- LLM inference latency

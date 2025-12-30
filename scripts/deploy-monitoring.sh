#!/bin/bash
# Quick deployment script for Loki + Grafana + Promtail

set -e

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-homebrain}"
K3S_MASTER="ubuntu@192.168.0.206"
NAS_MOUNT="/mnt/loki-logs"

echo "🚀 Deploying Loki + Grafana + Promtail..."

# Step 1: Verify NAS mount on k3s-master
echo "📍 Checking NAS mount on k3s-master..."
if ! ssh "$K3S_MASTER" test -d "$NAS_MOUNT"; then
    echo "❌ Error: $NAS_MOUNT not found on k3s-master"
    echo "Please mount the NAS first:"
    echo "  ssh $K3S_MASTER"
    echo "  sudo mkdir -p $NAS_MOUNT"
    echo "  sudo mount $NAS_MOUNT"
    exit 1
fi
echo "✅ NAS mount verified"

# Step 2: Deploy manifests
echo ""
echo "📦 Deploying Kubernetes manifests..."
kubectl --kubeconfig "$KUBECONFIG" apply -f k8s/monitoring/namespace.yaml
echo "  ✅ Namespace created"

kubectl --kubeconfig "$KUBECONFIG" apply -f k8s/monitoring/loki-config.yaml
echo "  ✅ Loki ConfigMap created"

kubectl --kubeconfig "$KUBECONFIG" apply -f k8s/monitoring/loki.yaml
echo "  ✅ Loki deployment started"

# Wait for Loki to be ready
echo "⏳ Waiting for Loki to be ready..."
kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=ready pod -l app=loki -n monitoring --timeout=60s
echo "✅ Loki is ready"

kubectl --kubeconfig "$KUBECONFIG" apply -f k8s/monitoring/promtail-config.yaml
kubectl --kubeconfig "$KUBECONFIG" apply -f k8s/monitoring/promtail.yaml
echo "  ✅ Promtail deployment started"

kubectl --kubeconfig "$KUBECONFIG" apply -f k8s/monitoring/grafana.yaml
echo "  ✅ Grafana deployment started"

# Step 3: Wait for all pods
echo ""
echo "⏳ Waiting for all pods to be ready..."
kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=ready pod -l app=promtail -n monitoring --timeout=60s
kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=60s
echo "✅ All pods are ready"

# Step 4: Show summary
echo ""
echo "✨ Deployment complete!"
echo ""
echo "📊 Grafana Access:"
echo "   Default user: admin"
echo "   Default password: admin"
echo ""

# Get service info
SERVICE_IP=$(kubectl --kubeconfig "$KUBECONFIG" get svc -n monitoring grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
SERVICE_PORT=$(kubectl --kubeconfig "$KUBECONFIG" get svc -n monitoring grafana -o jsonpath='{.spec.ports[0].port}')

if [ "$SERVICE_IP" != "pending" ] && [ ! -z "$SERVICE_IP" ]; then
    echo "   URL: http://$SERVICE_IP:$SERVICE_PORT"
else
    echo "   Use port-forward:"
    echo "   kubectl port-forward -n monitoring svc/grafana 3000:80"
    echo "   URL: http://localhost:3000"
fi

echo ""
echo "📝 Next steps:"
echo "   1. Login to Grafana"
echo "   2. Go to Explore → Select Loki datasource"
echo "   3. Try query: {namespace=\"immich\"}"
echo ""
echo "📚 Full guide: docs/MONITORING_SETUP.md"

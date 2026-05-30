#!/bin/bash
# Install kube-prometheus-stack with Tailscale access
# Access: https://monitoring.dove-komodo.ts.net

set -e

echo "🚀 Installing kube-prometheus-stack monitoring..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ helm not found. Please install helm first.${NC}"
    exit 1
fi

# Check cluster connectivity
echo -e "${YELLOW}Checking cluster connectivity...${NC}"
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to cluster. Check your kubeconfig.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Cluster connectivity OK${NC}"

# Create namespace
echo -e "${YELLOW}Creating monitoring namespace...${NC}"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Check for Tailscale auth key
echo -e "${YELLOW}Checking Tailscale auth key...${NC}"
if ! kubectl get secret tailscale-auth -n monitoring &> /dev/null; then
    echo -e "${RED}❌ Tailscale auth key secret not found!${NC}"
    echo ""
    echo "Please create a Tailscale auth key at: https://login.tailscale.com/admin/settings/keys"
    echo "Then run:"
    echo ""
    echo "  kubectl create secret generic tailscale-auth \\"
    echo "    --from-literal=TS_AUTHKEY='tskey-auth-YOUR-KEY-HERE' \\"
    echo "    -n monitoring"
    echo ""
    exit 1
fi
echo -e "${GREEN}✅ Tailscale auth key found${NC}"

# Apply Tailscale configuration
echo -e "${YELLOW}Applying Tailscale configuration...${NC}"
kubectl apply -f tailscale-config.yaml

# Add Prometheus community Helm repo
echo -e "${YELLOW}Adding Prometheus community Helm repo...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install or upgrade kube-prometheus-stack
echo -e "${YELLOW}Installing kube-prometheus-stack (this may take 3-5 minutes)...${NC}"
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kube-prometheus-values.yaml \
  --wait \
  --timeout 10m

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "📊 Monitoring Stack Status:"
kubectl get pods -n monitoring
echo ""
echo "🌐 Access Points:"
echo "  • Grafana:      https://monitoring.dove-komodo.ts.net"
echo "  • Username:     admin"
echo "  • Password:     admin (change in kube-prometheus-values.yaml)"
echo ""
echo "⚡ Next Steps:"
echo "  1. Wait for all pods to be Ready (check: kubectl get pods -n monitoring)"
echo "  2. Access Grafana via Tailscale: https://monitoring.dove-komodo.ts.net"
echo "  3. Login with admin/admin and change password"
echo "  4. Explore pre-built dashboards in Grafana"
echo "  5. Configure AlertManager notifications (see kube-prometheus-values.yaml)"
echo ""
echo "📚 Popular Dashboards to Check:"
echo "  • Node Exporter Full (all node metrics)"
echo "  • Kubernetes / Compute Resources / Cluster"
echo "  • Kubernetes / Compute Resources / Namespace (Pods)"
echo ""

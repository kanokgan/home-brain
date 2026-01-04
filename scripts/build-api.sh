#!/bin/bash
set -e

# Build multi-arch Docker image for homebrain-api

IMAGE_NAME="ghcr.io/kanokgan/homebrain-api"
VERSION="${1:-latest}"

echo "🏗️  Building homebrain-api:${VERSION} for ARM64 and AMD64..."

# Build for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ${IMAGE_NAME}:${VERSION} \
  --tag ${IMAGE_NAME}:latest \
  --push \
  --file backend/Dockerfile \
  backend/

echo "✅ Build complete!"
echo "📦 Image: ${IMAGE_NAME}:${VERSION}"
echo ""
echo "Next steps:"
echo "1. Commit and push k8s manifests to GitHub"
echo "2. Apply ArgoCD application: kubectl apply -f infrastructure/argocd/apps/homebrain-api.yaml"
echo "3. Watch deployment: kubectl get pods -n homebrain -w"

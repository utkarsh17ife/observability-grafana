#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

API_IMAGE="utkarsh17ife/java-otel-api-svc"
WORKER_IMAGE="utkarsh17ife/java-otel-worker-svc"
TAG="${1:-latest}"

echo "Building and pushing images with tag: $TAG"

# Build and push api-service
echo "Building $API_IMAGE:$TAG..."
docker build -t "$API_IMAGE:$TAG" "$SCRIPT_DIR/api-service"
echo "Pushing $API_IMAGE:$TAG..."
docker push "$API_IMAGE:$TAG"

# Build and push worker-service
echo "Building $WORKER_IMAGE:$TAG..."
docker build -t "$WORKER_IMAGE:$TAG" "$SCRIPT_DIR/worker-service"
echo "Pushing $WORKER_IMAGE:$TAG..."
docker push "$WORKER_IMAGE:$TAG"

echo "Done! Images pushed:"
echo "  - $API_IMAGE:$TAG"
echo "  - $WORKER_IMAGE:$TAG"

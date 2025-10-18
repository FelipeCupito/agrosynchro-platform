#!/bin/bash

# =============================================================================
# QUICK LOCAL BUILD FOR PROCESSING ENGINE
# =============================================================================
# Simple script to build and test locally
# =============================================================================

set -e

PROJECT_NAME="agrosynchro"
SERVICE_NAME="processing-engine"
IMAGE_NAME="${PROJECT_NAME}-${SERVICE_NAME}"

echo "Building Docker image..."
docker build -t $IMAGE_NAME:latest .

echo "Build completed!"
echo ""
echo "To test locally:"
echo "  docker run --rm -p 8080:8080 -e SQS_QUEUE_URL=test $IMAGE_NAME:latest"
echo ""
echo "To deploy to LocalStack:"
echo "  ./build-and-deploy.sh local"
echo ""
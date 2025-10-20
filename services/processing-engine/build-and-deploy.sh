#!/bin/bash

# =============================================================================
# BUILD AND DEPLOY TO ECR - Simple Version
# =============================================================================
# Builds Docker image and deploys to AWS ECR
# Usage: ./build-and-deploy.sh
# =============================================================================

set -e

PROJECT_NAME="agrosynchro"
SERVICE_NAME="processing-engine"
IMAGE_NAME="${PROJECT_NAME}-${SERVICE_NAME}"

echo "🚀 Starting ECR deployment for $IMAGE_NAME"

# Get AWS account and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY_NAME="${PROJECT_NAME}-${SERVICE_NAME}"
IMAGE_TAG="${ECR_REGISTRY}/${REPOSITORY_NAME}:latest"

echo "📦 Building Docker image for x86_64..."
docker build --platform linux/amd64 -t $IMAGE_NAME:latest .
docker tag $IMAGE_NAME:latest $IMAGE_TAG

echo "🔧 Setting up ECR..."
aws ecr create-repository --repository-name $REPOSITORY_NAME --region $AWS_REGION 2>/dev/null || true

echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

echo "⬆️  Pushing image..."
docker push $IMAGE_TAG

echo "🧹 Cleaning up..."
docker rmi $IMAGE_NAME:latest 2>/dev/null || true
docker rmi $IMAGE_TAG 2>/dev/null || true

echo "✅ Done! Image deployed to: $IMAGE_TAG"
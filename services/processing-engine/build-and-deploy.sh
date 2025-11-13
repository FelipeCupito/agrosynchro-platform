#!/usr/bin/env bash
set -euo pipefail

# 📁 Directorio del script actual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Building and deploying Processing Engine..."

AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_NAME="agrosynchro-processing-engine"
IMAGE_TAG="latest"

# Crear ECR si no existe
if ! aws ecr describe-repositories --repository-names "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "🆕 Creando repositorio ECR: $IMAGE_NAME"
  aws ecr create-repository --repository-name "$IMAGE_NAME" >/dev/null
  echo "✅ Repositorio ECR creado"
else
  echo "✅ Repositorio ECR ya existe"
fi



# 🔐 Login seguro a ECR
echo "🔐 Logging into ECR..."
DOCKER_CONFIG_FILE="$HOME/.docker/config.json"
if [ -f "$DOCKER_CONFIG_FILE" ]; then
  jq 'del(.credsStore, .credHelpers)' "$DOCKER_CONFIG_FILE" > "${DOCKER_CONFIG_FILE}.tmp" && mv "${DOCKER_CONFIG_FILE}.tmp" "$DOCKER_CONFIG_FILE"
else
  mkdir -p "$HOME/.docker"
  echo '{}' > "$DOCKER_CONFIG_FILE"
fi

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_URL"
echo "✅ Logged into ECR successfully."

# 🏗️ Build Docker image
echo "🐳 Building Docker image..."
docker build --platform linux/amd64 -t "${IMAGE_NAME}:${IMAGE_TAG}" "$SCRIPT_DIR"

# 🏷️ Tag and push image
echo "📦 Tagging and pushing image to ECR..."
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
docker push "${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "✅ Processing Engine built and pushed successfully to ECR."

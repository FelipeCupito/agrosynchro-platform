#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR"
AUTO_APPROVE=false
SKIP_INIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--auto-approve) AUTO_APPROVE=true; shift ;;
    --skip-init) SKIP_INIT=true; shift ;;
    -h|--help) echo "Uso: $0 [--auto-approve|-y] [--skip-init]"; exit 0 ;;
    *) echo "Argumento desconocido: $1"; exit 2 ;;
  esac
done

cd "$TF_DIR"

# -------------------------
# 0A: Build Frontend
# -------------------------
echo "🎨 Construyendo frontend..."
FRONTEND_DIR="$SCRIPT_DIR/../services/web-dashboard/frontend"
cd "$FRONTEND_DIR"
npm ci --production=false
npm run build
echo "✅ Frontend compilado"

# -------------------------
# 0B: Build & Deploy Processing Engine
# -------------------------
PROCESSING_DIR="$SCRIPT_DIR/../services/processing-engine"
cd "$PROCESSING_DIR"
chmod +x build-and-deploy.sh
./build-and-deploy.sh
echo "✅ Processing Engine desplegado (Docker + ECR)"

# -------------------------
# 1: Terraform init/apply
# -------------------------
cd "$TF_DIR"
if [[ "$SKIP_INIT" == "false" ]]; then
  terraform init
fi

# Variables para ECR
PROJECT_NAME="$(terraform output -raw project_name 2>/dev/null || echo "agrosynchro")"
ECR_REPO_NAME="${PROJECT_NAME}-processing-engine"
ECR_RESOURCE="module.fargate.aws_ecr_repository.processing_engine"

# Importar el repositorio ECR al state si no existe
if ! terraform state list | grep -q "$ECR_RESOURCE"; then
  if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" >/dev/null 2>&1; then
    echo "📦 Importando ECR al state de Terraform: $ECR_REPO_NAME"
    terraform import "$ECR_RESOURCE" "$ECR_REPO_NAME"
    echo "✅ ECR importado correctamente"
  else
    echo "🆕 El repositorio se creará durante el apply"
  fi
else
  echo "✅ ECR ya está en el state de Terraform"
fi

APPLY_ARGS=(apply)
[[ "$AUTO_APPROVE" == "true" ]] && APPLY_ARGS+=(-auto-approve)

terraform "${APPLY_ARGS[@]}"
echo "✅ Infraestructura desplegada con Terraform"

# -------------------------
# 2: Configuración Lambda Cognito
# -------------------------
COGNITO_DOMAIN="$(terraform output -raw cognito_domain 2>/dev/null || true)"
CLIENT_ID="$(terraform output -raw cognito_client_id 2>/dev/null || true)"
FRONTEND_URL="$(terraform output -raw frontend_website_url 2>/dev/null || true)"
REGION="$(terraform output -raw region 2>/dev/null || true)"
REGION="${REGION:-us-east-1}"

read -r -d '' ENV_JSON <<EOF || true
{"Variables":{"COGNITO_DOMAIN":"$COGNITO_DOMAIN","CLIENT_ID":"$CLIENT_ID","FRONTEND_URL":"$FRONTEND_URL"}}
EOF

aws lambda update-function-configuration \
  --function-name agrosynchro-cognito-callback \
  --environment "$ENV_JSON" \
  --region "$REGION" >/dev/null

# -------------------------
# 3: Inicialización DB
# -------------------------
aws lambda invoke \
  --function-name agrosynchro-init-db \
  --region "$REGION" \
  --payload '{}' \
  --output json \
  /tmp/init_db_response.json > /dev/null

echo "🎉 Despliegue completo listo. Frontend: $FRONTEND_URL"

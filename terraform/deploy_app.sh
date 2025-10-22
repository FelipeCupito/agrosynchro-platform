#!/usr/bin/env bash
set -euo pipefail

# deploy_app.sh - Despliegue completo de Agrosynchro Platform
# 
# Despliegue automatizado completo en múltiples fases:
# Fase 0A: Build del frontend React (npm run build)  
# Fase 0B: Build y deploy del processing engine (Docker + Fargate)
# Fase 1:  Deploy de infraestructura (terraform apply)
# Fase 2:  Configuración de Cognito (actualiza Lambda callback)
# Fase 3:  Inicialización de base de datos (ejecuta init_db Lambda)

AUTO_APPROVE=false
SKIP_INIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--auto-approve)
      AUTO_APPROVE=true; shift ;;
    --skip-init)
      SKIP_INIT=true; shift ;;
    -h|--help)
      echo "Uso: $0 [--auto-approve|-y] [--skip-init]"
      echo ""
      echo "Despliegue completo de Agrosynchro Platform:"
      echo "  • Build del frontend React"
      echo "  • Build y deploy del processing engine"
      echo "  • Deploy de infraestructura AWS"
      echo "  • Configuración automática de Cognito"
      echo "  • Inicialización de base de datos"
      echo ""
      echo "Opciones:"
      echo "  -y, --auto-approve  No pedir confirmación en terraform apply"
      echo "  --skip-init         Saltar terraform init"
      exit 0 ;;
    *)
      echo "Argumento desconocido: $1"; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR"

if [[ ! -f "$TF_DIR/main.tf" ]]; then
  echo "❌ No se encontró main.tf en: $TF_DIR" >&2
  exit 1
fi

cd "$TF_DIR"

command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform no está instalado o no está en PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI no está instalado o no está en PATH" >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "❌ npm no está instalado o no está en PATH" >&2; exit 1; }

# Fase 0A: Build del Frontend
echo "🎨 Construyendo frontend (npm run build)"
FRONTEND_DIR="$SCRIPT_DIR/../services/web-dashboard/frontend"
if [[ -d "$FRONTEND_DIR" ]]; then
  cd "$FRONTEND_DIR"
  if [[ -f "package.json" ]]; then
    echo "📦 Instalando dependencias del frontend..."
    npm ci --production=false
    echo "🔨 Compilando aplicación React..."
    npm run build
    echo "✅ Frontend compilado exitosamente"
  else
    echo "❌ No se encontró package.json en: $FRONTEND_DIR" >&2
    exit 1
  fi
else
  echo "❌ No se encontró directorio del frontend: $FRONTEND_DIR" >&2
  exit 1
fi

# Fase 0B: Build y deploy del Processing Engine
echo "⚙️ Construyendo y desplegando processing engine"
PROCESSING_DIR="$SCRIPT_DIR/../services/processing-engine"
if [[ -d "$PROCESSING_DIR" && -f "$PROCESSING_DIR/build-and-deploy.sh" ]]; then
  cd "$PROCESSING_DIR"
  chmod +x build-and-deploy.sh
  echo "🐳 Ejecutando build-and-deploy.sh..."
  ./build-and-deploy.sh
  echo "✅ Processing engine desplegado exitosamente"
else
  echo "❌ No se encontró build-and-deploy.sh en: $PROCESSING_DIR" >&2
  exit 1
fi

# Volver al directorio de Terraform
cd "$TF_DIR"

if [[ "$SKIP_INIT" == "false" ]]; then
  echo "🔧 terraform init"
  terraform init
else
  echo "⚠️  Saltando terraform init (por --skip-init)"
fi

# Verificar e importar repositorio ECR existente si es necesario
echo "🔍 Verificando repositorio ECR existente..."
PROJECT_NAME="$(terraform output -raw project_name 2>/dev/null || echo "agrosynchro")"
ECR_REPO_NAME="${PROJECT_NAME}-processing-engine"

# Verificar si el recurso ya está en el estado de Terraform
if ! terraform state show "module.fargate.aws_ecr_repository.processing_engine" >/dev/null 2>&1; then
  # Verificar si el repositorio existe en AWS
  if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" >/dev/null 2>&1; then
    echo "📦 Importando repositorio ECR existente: $ECR_REPO_NAME"
    terraform import module.fargate.aws_ecr_repository.processing_engine "$ECR_REPO_NAME"
    echo "✅ Repositorio ECR importado exitosamente"
  else
    echo "🆕 El repositorio ECR se creará durante el apply"
  fi
else
  echo "✅ Repositorio ECR ya está en el estado de Terraform"
fi

APPLY_ARGS=(apply)
if [[ "$AUTO_APPROVE" == "true" ]]; then APPLY_ARGS+=(-auto-approve); fi

echo "🚀 terraform ${APPLY_ARGS[*]}"
terraform "${APPLY_ARGS[@]}"

echo "🔍 Leyendo outputs de Terraform"
COGNITO_DOMAIN="$(terraform output -raw cognito_domain 2>/dev/null || true)"
CLIENT_ID="$(terraform output -raw cognito_client_id 2>/dev/null || true)"
FRONTEND_URL="$(terraform output -raw frontend_website_url 2>/dev/null || true)"
REGION="$(terraform output -raw region 2>/dev/null || true)"

if [[ -z "${REGION:-}" ]]; then REGION="us-east-1"; fi

if [[ -z "${COGNITO_DOMAIN:-}" || -z "${CLIENT_ID:-}" || -z "${FRONTEND_URL:-}" ]]; then
  echo "❌ No se pudieron obtener outputs requeridos. Valores leídos:" >&2
  echo "   COGNITO_DOMAIN='$COGNITO_DOMAIN'" >&2
  echo "   CLIENT_ID     ='$CLIENT_ID'" >&2
  echo "   FRONTEND_URL  ='$FRONTEND_URL'" >&2
  exit 1
fi

echo "✅ Outputs OK"
echo "   COGNITO_DOMAIN: $COGNITO_DOMAIN"
echo "   CLIENT_ID     : $CLIENT_ID"
echo "   FRONTEND_URL  : $FRONTEND_URL"
echo "   REGION        : $REGION"

echo "🔁 Actualizando Lambda 'agrosynchro-cognito-callback' con variables reales"

read -r -d '' ENV_JSON <<EOF || true
{"Variables":{"COGNITO_DOMAIN":"$COGNITO_DOMAIN","CLIENT_ID":"$CLIENT_ID","FRONTEND_URL":"$FRONTEND_URL"}}
EOF

aws lambda update-function-configuration \
  --function-name agrosynchro-cognito-callback \
  --environment "$ENV_JSON" \
  --region "$REGION" >/dev/null

echo "🗃️ Ejecutando inicialización de base de datos"

# Ejecutar la lambda init_db para inicializar la base de datos
aws lambda invoke \
  --function-name agrosynchro-init-db \
  --region "$REGION" \
  --payload '{}' \
  --output json \
  /tmp/init_db_response.json > /dev/null

# Verificar el resultado
if aws logs filter-log-events \
  --log-group-name "/aws/lambda/agrosynchro-init-db" \
  --start-time $(($(date +%s) - 300)) \
  --region "$REGION" \
  --query 'events[0].message' \
  --output text 2>/dev/null | grep -q "SUCCESS\|created\|initialized" ; then
  echo "✅ Base de datos inicializada correctamente"
else
  echo "⚠️  Inicialización de BD ejecutada (verificar logs si hay problemas)"
fi

echo "🎉 Proceso completado"
echo "Resumen de despliegue completo:"
echo "  0A) Frontend compilado (npm run build)"
echo "  0B) Processing Engine desplegado (Docker + Fargate)"
echo "  1)  Infraestructura desplegada (terraform apply)"
echo "  2)  Lambda de callback actualizada con variables de Cognito"
echo "  3)  Base de datos inicializada (init_db Lambda)"
echo ""
echo "🚀 Toda la aplicación Agrosynchro está desplegada y lista!"
echo "Puedes probar el flujo OAuth en: $FRONTEND_URL"

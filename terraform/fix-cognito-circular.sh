#!/usr/bin/env bash
set -euo pipefail

# fix-cognito-circular.sh
# Despliegue en 2 fases para romper la dependencia circular Cognito ⇄ API Gateway ⇄ Lambda
# Fase 1: terraform apply con campos de Cognito vacíos (ya definidos en main.tf)
# Fase 2: lee outputs y actualiza variables de entorno de la Lambda de callback

AUTO_APPROVE=false
SKIP_INIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--auto-approve)
      AUTO_APPROVE=true; shift ;;
    --skip-init)
      SKIP_INIT=true; shift ;;
    -h|--help)
      echo "Uso: $0 [--auto-approve|-y] [--skip-init]"; exit 0 ;;
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

if [[ "$SKIP_INIT" == "false" ]]; then
  echo "🔧 terraform init"
  terraform init
else
  echo "⚠️  Saltando terraform init (por --skip-init)"
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

echo "🎉 Proceso completado"
echo "Resumen:"
echo "  1) terraform apply ejecutado (Fase 1)"
echo "  2) Lambda de callback actualizada con COGNITO_DOMAIN/CLIENT_ID/FRONTEND_URL (Fase 2)"
echo ""
echo "Puedes probar el flujo OAuth en: $FRONTEND_URL"

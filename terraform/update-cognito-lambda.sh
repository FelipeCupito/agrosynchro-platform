#!/bin/bash
# Script para actualizar las variables de entorno de la Lambda callback después del primer apply

set -e

echo "🔍 Obteniendo valores de Cognito y API Gateway..."

COGNITO_DOMAIN=$(terraform output -raw cognito_domain 2>/dev/null || echo "")
CLIENT_ID=$(terraform output -raw cognito_client_id 2>/dev/null || echo "")
FRONTEND_URL=$(terraform output -raw frontend_website_url 2>/dev/null || echo "")

if [ -z "$COGNITO_DOMAIN" ] || [ -z "$CLIENT_ID" ] || [ -z "$FRONTEND_URL" ]; then
  echo "❌ Error: No se pudieron obtener los valores de Terraform outputs"
  echo "COGNITO_DOMAIN: $COGNITO_DOMAIN"
  echo "CLIENT_ID: $CLIENT_ID"
  echo "FRONTEND_URL: $FRONTEND_URL"
  exit 1
fi

echo "✅ Valores obtenidos:"
echo "  COGNITO_DOMAIN: $COGNITO_DOMAIN"
echo "  CLIENT_ID: $CLIENT_ID"
echo "  FRONTEND_URL: $FRONTEND_URL"

echo ""
echo "🚀 Actualizando Lambda agrosynchro-cognito-callback..."

aws lambda update-function-configuration \
  --function-name agrosynchro-cognito-callback \
  --environment "Variables={COGNITO_DOMAIN=$COGNITO_DOMAIN,CLIENT_ID=$CLIENT_ID,FRONTEND_URL=$FRONTEND_URL}" \
  --region us-east-1

echo "✅ Lambda actualizada correctamente"

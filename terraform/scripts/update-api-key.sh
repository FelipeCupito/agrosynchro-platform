#!/bin/bash

if [ -z "$1" ]; then
    echo "❌ Uso: $0 <API_KEY>"
    exit 1
fi

API_KEY="$1"

# Ruta absoluta del script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Archivo real
TFVARS_FILE="${SCRIPT_DIR}/modules/lambda/terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "❌ No existe $TFVARS_FILE"
    exit 1
fi

echo "🔐 Actualizando api_key en $TFVARS_FILE..."

# reemplaza la key
sed -i.bak "s/^api_key.*/api_key = \"${API_KEY}\"/" "$TFVARS_FILE"

echo "🚀 Ejecutando terraform apply..."
terraform apply -auto-approve

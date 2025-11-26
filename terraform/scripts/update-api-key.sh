#!/bin/bash

if [ -z "$1" ]; then
    echo "❌ Uso: $0 <API_KEY>"
    exit 1
fi

API_KEY="$1"

# Directorio donde está este script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Root del proyecto = un nivel arriba del script
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Path RELATIVO al root del proyecto
TFVARS_FILE="${PROJECT_ROOT}/terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "❌ No existe el archivo: $TFVARS_FILE"
    exit 1
fi

echo "🔐 Actualizando api_key en $TFVARS_FILE..."

# Reemplaza la key
sed -i.bak "s/^api_key.*/api_key = \"${API_KEY}\"/" "$TFVARS_FILE"

echo "🚀 Ejecutando terraform apply desde ${PROJECT_ROOT}..."
terraform -chdir="$PROJECT_ROOT" apply -auto-approve
#!/bin/bash

if [ -z "$1" ]; then
    echo "❌ Uso: $0 <API_KEY>"
    exit 1
fi

API_KEY="$1"

# Directorio donde está este script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Root del proyecto = un nivel arriba del script
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Path RELATIVO al root del proyecto
TFVARS_FILE="${PROJECT_ROOT}/terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "❌ No existe el archivo: $TFVARS_FILE"
    exit 1
fi

echo "🔐 Actualizando api_key en $TFVARS_FILE..."

# Reemplaza la key
sed -i.bak "s/^api_key.*/api_key = \"${API_KEY}\"/" "$TFVARS_FILE"

echo "🚀 Ejecutando terraform apply desde ${PROJECT_ROOT}..."
terraform -chdir="$PROJECT_ROOT" apply -auto-approve

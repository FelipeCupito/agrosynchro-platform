#!/bin/bash

# =============================================================================
# SCRIPT: SEND SENSOR DATA (POST to API Gateway /images)
# Descripción: Envía mensajes de datos de sensores a la API Gateway (POST /images) durante 10 minutos
# Usage: ./send_sensor_data.sh [--date DD-MM-YYYY]
# =============================================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}    AGROSYNCHRO - SENSOR DATA GENERATOR${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""

# Parsear argumentos
CUSTOM_DATE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --date)
            CUSTOM_DATE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--date DD-MM-YYYY]"
            echo ""
            echo "Options:"
            echo "  --date DD-MM-YYYY    Usar fecha específica (default: hoy)"
            echo "  -h, --help           Mostrar esta ayuda"
            echo ""
            echo "Example:"
            echo "  $0                    # Usa fecha de hoy"
            echo "  $0 --date 15-11-2025  # Usa fecha específica"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Error: Argumento desconocido '$1'${NC}"
            echo "Use --help para ver opciones disponibles"
            exit 1
            ;;
    esac
done

# Validar y convertir fecha si se proporcionó
TARGET_DATE=""
if [ -n "$CUSTOM_DATE" ]; then
    # Validar formato DD-MM-YYYY
    if [[ ! "$CUSTOM_DATE" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{4}$ ]]; then
        echo -e "${RED}❌ Error: Formato de fecha inválido${NC}"
        echo -e "${YELLOW}💡 Use formato: DD-MM-YYYY (ejemplo: 15-11-2025)${NC}"
        exit 1
    fi
    
    # Convertir DD-MM-YYYY a YYYY-MM-DD para uso interno
    DAY=$(echo "$CUSTOM_DATE" | cut -d'-' -f1)
    MONTH=$(echo "$CUSTOM_DATE" | cut -d'-' -f2)
    YEAR=$(echo "$CUSTOM_DATE" | cut -d'-' -f3)
    TARGET_DATE="${YEAR}-${MONTH}-${DAY}"
    
    # Validar que la fecha sea válida
    if ! date -j -f "%Y-%m-%d" "$TARGET_DATE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: Fecha inválida${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}📅 Usando fecha personalizada: ${CUSTOM_DATE}${NC}"
else
    # Usar fecha de hoy
    TARGET_DATE=$(date +"%Y-%m-%d")
    echo -e "${GREEN}📅 Usando fecha de hoy: $(date +"%d-%m-%Y")${NC}"
fi
echo ""

# Función para generar timestamp ISO 8601 con la fecha objetivo
generate_timestamp() {
    local base_date="$1"
    local time_part=$(date +"%H:%M:%S")
    echo "${base_date}T${time_part}Z"
}

# Función para generar valores aleatorios de sensores
generate_sensor_data() {
    local user_id=$1
    local target_date=$2
    local timestamp=$(generate_timestamp "$target_date")
    
    # Generar valores aleatorios realistas (usar awk en vez de bc, más portable)
    local r1=$RANDOM; local r2=$RANDOM
    local temperature=$(awk -v a=15 -v r1="$r1" -v r2="$r2" 'BEGIN{printf "%.1f", a + (r1%30) + (r2%100)/100}')
    local r3=$RANDOM; local r4=$RANDOM
    local humidity=$(awk -v a=30 -v r1="$r3" -v r2="$r4" 'BEGIN{printf "%.1f", a + (r1%70) + (r2%100)/100}')
    local r5=$RANDOM; local r6=$RANDOM
    local soil_moisture=$(awk -v a=20 -v r1="$r5" -v r2="$r6" 'BEGIN{printf "%.1f", a + (r1%80) + (r2%100)/100}')
    
    # Crear JSON
    cat <<EOF
{
    "user_id": ${user_id},
    "timestamp": "${timestamp}",
    "temperature": ${temperature},
    "humidity": ${humidity},
    "soil_moisture": ${soil_moisture}
}
EOF
}

# Función para enviar mensaje a API Gateway (POST /images)
send_to_api() {
    local api_base_url=$1
    local message=$2

    # Construir argumentos de curl
    local url="${api_base_url%/}/messages"
    # Ejecutar curl y capturar body + http code (separador '||')
    local response
    if [ -n "$API_KEY" ]; then
        response=$(curl -sS -X POST "$url" -H "Content-Type: application/json" -H "Authorization: ${API_KEY}" -d "$message" -w "||%{http_code}")
    else
        response=$(curl -sS -X POST "$url" -H "Content-Type: application/json" -d "$message" -w "||%{http_code}")
    fi

    # Separar body y código
    LAST_BODY="${response%||*}"
    HTTP_CODE="${response##*||}"
    echo "$HTTP_CODE"
}

# Validar que estamos en el directorio correcto
if [ ! -f "main.tf" ]; then
    echo -e "${RED}❌ Error: Este script debe ejecutarse desde el directorio de Terraform${NC}"
    echo -e "${YELLOW}💡 Cambia al directorio: cd terraform${NC}"
    exit 1
fi

# Obtener URL base de la API Gateway (o usar API_URL env)
echo -e "${YELLOW}🔍 Obteniendo URL de la API Gateway (desde Terraform)...${NC}"
DEFAULT_API_BASE_URL=$(terraform output -raw api_gateway_invoke_url)

API_BASE_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null || true)
if [ -z "$API_BASE_URL" ]; then
    API_BASE_URL=$(terraform output -raw api_invoke_url 2>/dev/null || true)
fi

if [ -z "$API_BASE_URL" ]; then
    if [ -n "$DEFAULT_API_BASE_URL" ]; then
        API_BASE_URL="$DEFAULT_API_BASE_URL"
        echo -e "${YELLOW}⚠️ Usando URL hardcodeada: ${API_BASE_URL}${NC}"
    else
        echo -e "${RED}❌ Error: No se pudo obtener la URL de la API Gateway desde Terraform y no hay URL hardcodeada${NC}"
        echo -e "${YELLOW}💡 Ejecuta: terraform output -raw api_gateway_invoke_url  o establece DEFAULT_API_BASE_URL en el script${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ API Gateway encontrada: ${API_BASE_URL}${NC}"
echo ""

# Solicitar user_id
while true; do
    echo -e "${BLUE}👤 Ingresa el User ID:${NC}"
    read -p "user_id: " USER_ID
    
    # Validar que sea un número
    if [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
        break
    else
        echo -e "${RED}❌ Error: El User ID debe ser un número entero${NC}"
        echo ""
    fi
done

echo ""
echo -e "${GREEN}🚀 Iniciando envío de datos de sensores...${NC}"
echo -e "${YELLOW}📊 User ID: ${USER_ID}${NC}"
echo -e "${YELLOW}📅 Fecha objetivo: ${TARGET_DATE}${NC}"
echo -e "${YELLOW}⏱️  Duración: 10 minutos${NC}"
echo -e "${YELLOW}🔄 Intervalo: 10 segundos${NC}"
echo -e "${YELLOW}🎯 Endpoint: ${API_BASE_URL%/}/images${NC}"
echo ""

# Verificar que AWS CLI esté configurado
aws sts get-caller-identity >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: AWS CLI no está configurado correctamente${NC}"
    echo -e "${YELLOW}💡 Ejecuta: aws configure${NC}"
    exit 1
fi

# Variables de control
START_TIME=$(date +%s)
END_TIME=$((START_TIME + 600)) # 10 minutos = 600 segundos
MESSAGE_COUNT=0
SUCCESS_COUNT=0
ERROR_COUNT=0

echo -e "${GREEN}✅ Comenzando envío de mensajes...${NC}"
echo ""

# Bucle principal - enviar mensajes cada 10 segundos durante 10 minutos
while [ $(date +%s) -lt $END_TIME ]; do
    MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
    CURRENT_TIME=$(date "+%H:%M:%S")
    
    # Generar datos del sensor
    SENSOR_DATA=$(generate_sensor_data $USER_ID "$TARGET_DATE")
    
    echo -e "${BLUE}📤 [$CURRENT_TIME] Enviando mensaje #${MESSAGE_COUNT}...${NC}"
    echo -e "${YELLOW}   Datos: $(echo $SENSOR_DATA | tr -d '\n' | tr -s ' ')${NC}"
    
    # Enviar mensaje a API Gateway (POST /images)
    HTTP_CODE=$(send_to_api "$API_BASE_URL" "$SENSOR_DATA")

    if [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] && [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo -e "${GREEN}   ✅ Enviado exitosamente - HTTP ${HTTP_CODE}${NC}"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo -e "${RED}   ❌ Error al enviar mensaje - HTTP ${HTTP_CODE}${NC}"
        # Mostrar cuerpo de respuesta para depuración
        if [ -n "${LAST_BODY}" ]; then
            echo -e "${YELLOW}   ➜ Response body:${NC} ${LAST_BODY}"
        fi
    fi
    
    echo ""
    
    # Verificar si quedan al menos 30 segundos
    REMAINING_TIME=$((END_TIME - $(date +%s)))
    if [ $REMAINING_TIME -lt 30 ]; then
        echo -e "${YELLOW}⏰ Tiempo restante menor a 30 segundos. Finalizando...${NC}"
        break
    fi
    
    # Esperar 10 segundos
    echo -e "${YELLOW}⏳ Esperando 10 segundos para el próximo mensaje...${NC}"
    sleep 10
done

# Resumen final
echo ""
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}                    RESUMEN FINAL${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}✅ Mensajes enviados exitosamente: ${SUCCESS_COUNT}${NC}"
echo -e "${RED}❌ Mensajes con error: ${ERROR_COUNT}${NC}"
echo -e "${YELLOW}📊 Total de mensajes procesados: ${MESSAGE_COUNT}${NC}"
echo -e "${YELLOW}👤 User ID utilizado: ${USER_ID}${NC}"
echo -e "${YELLOW}🎯 Endpoint utilizado: ${API_BASE_URL%/}/images${NC}"
echo ""

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}🎉 ¡Proceso completado exitosamente!${NC}"
else
    echo -e "${YELLOW}⚠️  Proceso completado con algunos errores${NC}"
fi

echo ""
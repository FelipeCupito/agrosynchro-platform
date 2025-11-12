#!/bin/bash

# =============================================================================
# SCRIPT: SEND SENSOR DATA TO SQS QUEUE
# Descripción: Envía mensajes de datos de sensores a la cola SQS durante 10 minutos
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

# Función para generar timestamp ISO 8601
generate_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Función para generar valores aleatorios de sensores
generate_sensor_data() {
    local user_id=$1
    local timestamp=$(generate_timestamp)
    
    # Generar valores aleatorios realistas
    local temperature=$(echo "scale=1; 15 + $RANDOM % 30 + ($RANDOM % 100) / 100" | bc)
    local humidity=$(echo "scale=1; 30 + $RANDOM % 70 + ($RANDOM % 100) / 100" | bc)
    local soil_moisture=$(echo "scale=1; 20 + $RANDOM % 80 + ($RANDOM % 100) / 100" | bc)
    
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

# Función para enviar mensaje a SQS
send_to_sqs() {
    local queue_url=$1
    local message=$2
    
    aws sqs send-message \
        --queue-url "$queue_url" \
        --message-body "$message" \
        --output text --query 'MessageId' 2>/dev/null
}

# Validar que estamos en el directorio correcto
if [ ! -f "main.tf" ]; then
    echo -e "${RED}❌ Error: Este script debe ejecutarse desde el directorio de Terraform${NC}"
    echo -e "${YELLOW}💡 Cambia al directorio: cd terraform${NC}"
    exit 1
fi

# Obtener URL de la cola SQS
echo -e "${YELLOW}🔍 Obteniendo URL de la cola SQS...${NC}"
SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$SQS_QUEUE_URL" ]; then
    echo -e "${RED}❌ Error: No se pudo obtener la URL de la cola SQS${NC}"
    echo -e "${YELLOW}💡 Asegúrate de que la infraestructura esté desplegada: terraform apply${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Cola SQS encontrada: ${SQS_QUEUE_URL}${NC}"
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
echo -e "${YELLOW}⏱️  Duración: 10 minutos${NC}"
echo -e "${YELLOW}🔄 Intervalo: 10 segundos${NC}"
echo -e "${YELLOW}🎯 Cola: ${SQS_QUEUE_URL}${NC}"
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

# Bucle principal - enviar mensajes cada 30 segundos durante 10 minutos
while [ $(date +%s) -lt $END_TIME ]; do
    MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
    CURRENT_TIME=$(date "+%H:%M:%S")
    
    # Generar datos del sensor
    SENSOR_DATA=$(generate_sensor_data $USER_ID)
    
    echo -e "${BLUE}📤 [$CURRENT_TIME] Enviando mensaje #${MESSAGE_COUNT}...${NC}"
    echo -e "${YELLOW}   Datos: $(echo $SENSOR_DATA | tr -d '\n' | tr -s ' ')${NC}"
    
    # Enviar mensaje a SQS
    MESSAGE_ID=$(send_to_sqs "$SQS_QUEUE_URL" "$SENSOR_DATA")
    
    if [ $? -eq 0 ] && [ -n "$MESSAGE_ID" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo -e "${GREEN}   ✅ Enviado exitosamente - ID: ${MESSAGE_ID}${NC}"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo -e "${RED}   ❌ Error al enviar mensaje${NC}"
    fi
    
    echo ""
    
    # Verificar si quedan al menos 30 segundos
    REMAINING_TIME=$((END_TIME - $(date +%s)))
    if [ $REMAINING_TIME -lt 30 ]; then
        echo -e "${YELLOW}⏰ Tiempo restante menor a 30 segundos. Finalizando...${NC}"
        break
    fi
    
    # Esperar 30 segundos
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
echo -e "${YELLOW}🎯 Cola utilizada: ${SQS_QUEUE_URL}${NC}"
echo ""

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}🎉 ¡Proceso completado exitosamente!${NC}"
else
    echo -e "${YELLOW}⚠️  Proceso completado con algunos errores${NC}"
fi

echo ""
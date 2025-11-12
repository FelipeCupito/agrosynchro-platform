#!/usr/bin/env bash

# =============================================================================
# AGROSYNCHRO - UPDATE LAMBDA FUNCTIONS
# =============================================================================
# Propósito: Actualizar código de funciones Lambda sin tocar infraestructura
# Uso: Para desarrollo cuando cambias código Python de las Lambdas
# =============================================================================

set -euo pipefail

# Colores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Directorios
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SERVICES_DIR="$PROJECT_ROOT/services"

# Variables globales
declare -a UPDATED_FUNCTIONS=()
FORCE_UPDATE=false
SPECIFIC_FUNCTION=""

log() { echo -e "$1" >&2; }
log_info() { log "${BLUE}ℹ️  $1${NC}"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_error() { log "${RED}❌ $1${NC}"; }
log_debug() { log "${PURPLE}🔍 $1${NC}"; }

show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║           ⚡ LAMBDA UPDATE - DESARROLLO                      ║
║                                                              ║
║  Actualizar código de Lambdas sin tocar infraestructura     ║
║  🔄 Solo reempaqueta y sube código nuevo                    ║
║  🚀 Ideal para iteración rápida                             ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

show_help() {
    cat << 'EOF'
MODO DE USO:
  ./update-lambdas.sh [OPCIONES] [FUNCIÓN]

OPCIONES:
  -f, --force           Forzar actualización aunque no hay cambios detectados
  -h, --help           Mostrar esta ayuda

FUNCIONES DISPONIBLES:
  api                   Lambda principal del API
  users-post            Endpoint para crear usuarios
  parameters-get        Obtener parámetros del sistema
  parameters-post       Guardar parámetros del sistema  
  sensor-data-get       Obtener datos de sensores
  report-field          Generar reporte de campo
  reports-get           Obtener reportes existentes
  drone-image-upload    Procesamiento de imágenes de drone
  cognito-callback      Callback OAuth de Cognito
  init-db               Inicialización de base de datos
  all                   Actualizar todas las funciones

EJEMPLOS:
  ./update-lambdas.sh                    # Actualizar todas las funciones
  ./update-lambdas.sh api                # Solo actualizar la Lambda 'api'
  ./update-lambdas.sh --force all        # Forzar actualización de todas
  ./update-lambdas.sh -f users-post      # Forzar actualización de users-post

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_UPDATE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$SPECIFIC_FUNCTION" ]]; then
                    SPECIFIC_FUNCTION="$1"
                else
                    log_error "Solo se puede especificar una función a la vez"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Si no se especifica función, actualizar todas
    if [[ -z "$SPECIFIC_FUNCTION" ]]; then
        SPECIFIC_FUNCTION="all"
    fi
}

validate_prerequisites() {
    log_info "Validando prerequisitos..."
    
    # Verificar herramientas
    local missing_tools=()
    for tool in "aws" "zip" "terraform"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Herramientas faltantes: ${missing_tools[*]}"
        exit 1
    fi
    
    # Verificar AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI no configurado o sin permisos"
        log_info "Ejecutar: aws configure"
        exit 1
    fi
    
    # Verificar que Terraform está inicializado
    cd "$SCRIPT_DIR/.."
    if [[ ! -f ".terraform.lock.hcl" ]]; then
        log_error "Terraform no está inicializado"
        log_info "Ejecutar: terraform init"
        exit 1
    fi
    
    log_success "Prerequisitos validados"
}

get_terraform_outputs() {
    log_info "Obteniendo configuración desde Terraform..."
    
    cd "$SCRIPT_DIR/.."
    
    # Verificar que la infraestructura está desplegada
    if ! terraform output >/dev/null 2>&1; then
        log_error "Infraestructura no está desplegada"
        log_info "Ejecutar primero: ./deploy.sh"
        exit 1
    fi
    
    # Obtener región
    REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
    PROJECT_NAME=$(terraform output -raw environment 2>/dev/null | sed 's/aws/agrosynchro/' || echo "agrosynchro")
    
    log_success "Configuración obtenida (Region: $REGION)"
}

# Definir funciones Lambda y sus archivos fuente
declare -A LAMBDA_FUNCTIONS=(
    ["api"]="lambda-app:app.py"
    ["users-post"]="lambda-app:users_post.py"
    ["parameters-get"]="lambda-app:parameters_get.py"
    ["parameters-post"]="lambda-app:parameters_post.py"
    ["sensor-data-get"]="lambda-app:sensor_data_get.py"
    ["report-field"]="lambda-app:report_field.py"
    ["reports-get"]="lambda-app:reports_get.py"
    ["drone-image-upload"]="iot-gateway:lambda_upload.py"
    ["cognito-callback"]="cognito-callback:callback.py"
    ["init-db"]="lambda-app:init_db.py"
)

update_lambda_function() {
    local function_key="$1"
    local function_name="$PROJECT_NAME-$function_key"
    
    # Verificar que la función existe en AWS
    if ! aws lambda get-function --function-name "$function_name" --region "$REGION" >/dev/null 2>&1; then
        log_warning "Función Lambda '$function_name' no existe - saltando"
        return 1
    fi
    
    local source_info="${LAMBDA_FUNCTIONS[$function_key]}"
    local service_dir=$(echo "$source_info" | cut -d':' -f1)
    local main_file=$(echo "$source_info" | cut -d':' -f2)
    
    local function_dir="$SERVICES_DIR/$service_dir"
    local zip_file="/tmp/${function_name}-$(date +%s).zip"
    
    if [[ ! -d "$function_dir" ]]; then
        log_error "Directorio no encontrado: $function_dir"
        return 1
    fi
    
    log_info "📦 Empaquetando función '$function_key'..."
    
    # Crear ZIP según el tipo de función
    cd "$function_dir"
    
    if [[ "$service_dir" == "lambda-app" ]]; then
        # Para lambda-app, incluir todo el directorio
        zip -r "$zip_file" . -x "*.pyc" "__pycache__/*" "*.git*" "tests/*" >/dev/null 2>&1
    else
        # Para funciones individuales, solo el archivo específico
        if [[ ! -f "$main_file" ]]; then
            log_error "Archivo no encontrado: $function_dir/$main_file"
            return 1
        fi
        zip "$zip_file" "$main_file" >/dev/null 2>&1
    fi
    
    local zip_size=$(stat -f%z "$zip_file" 2>/dev/null || stat -c%s "$zip_file" 2>/dev/null)
    log_debug "ZIP creado: $zip_file ($(numfmt --to=iec $zip_size))"
    
    # Actualizar función en AWS
    log_info "🚀 Actualizando función '$function_name'..."
    
    if aws lambda update-function-code \
        --function-name "$function_name" \
        --zip-file "fileb://$zip_file" \
        --region "$REGION" >/dev/null 2>&1; then
        
        log_success "✅ '$function_key' actualizada correctamente"
        UPDATED_FUNCTIONS+=("$function_key")
        
        # Limpiar archivo temporal
        rm -f "$zip_file"
        return 0
    else
        log_error "Failed to update function '$function_name'"
        rm -f "$zip_file"
        return 1
    fi
}

update_functions() {
    log_info "🔄 Iniciando actualización de funciones Lambda..."
    echo ""
    
    local functions_to_update=()
    
    if [[ "$SPECIFIC_FUNCTION" == "all" ]]; then
        # Actualizar todas las funciones
        for func in "${!LAMBDA_FUNCTIONS[@]}"; do
            functions_to_update+=("$func")
        done
    else
        # Verificar que la función especificada existe
        if [[ ! -v "LAMBDA_FUNCTIONS[$SPECIFIC_FUNCTION]" ]]; then
            log_error "Función '$SPECIFIC_FUNCTION' no reconocida"
            log_info "Funciones disponibles: ${!LAMBDA_FUNCTIONS[*]}"
            exit 1
        fi
        functions_to_update+=("$SPECIFIC_FUNCTION")
    fi
    
    # Actualizar funciones
    local total=${#functions_to_update[@]}
    local current=0
    
    for func in "${functions_to_update[@]}"; do
        ((current++))
        log_info "[$current/$total] Procesando función: $func"
        update_lambda_function "$func" || true  # Continuar aunque una función falle
        echo ""
    done
}

show_summary() {
    echo ""
    log_info "📋 RESUMEN DE ACTUALIZACIÓN:"
    echo ""
    
    if [[ ${#UPDATED_FUNCTIONS[@]} -eq 0 ]]; then
        log_warning "No se actualizaron funciones"
    else
        log_success "Funciones actualizadas exitosamente:"
        for func in "${UPDATED_FUNCTIONS[@]}"; do
            log_success "  ✓ $func"
        done
    fi
    
    echo ""
    log_info "💡 TIPS:"
    log_info "   • Verificar logs en CloudWatch si hay problemas"
    log_info "   • Probar endpoints después de actualizar"
    log_info "   • Para Fargate usar: ./update-docker-ecr.sh"
    echo ""
}

main() {
    show_banner
    
    parse_arguments "$@"
    
    log_info "🚀 Configuración:"
    log_info "  Función objetivo: $SPECIFIC_FUNCTION"
    log_info "  Forzar actualización: $FORCE_UPDATE"
    echo ""
    
    validate_prerequisites
    get_terraform_outputs
    update_functions
    show_summary
    
    log_success "🎉 Proceso completado!"
}

# Ejecutar función principal con todos los argumentos
main "$@"
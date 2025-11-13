#!/usr/bin/env bash

# =============================================================================
# AGROSYNCHRO - UPDATE DOCKER ECR
# =============================================================================
# Propósito: Actualizar imagen Docker del processing engine en ECR
# Uso: Para desarrollo cuando cambias código de Fargate/processing
# =============================================================================

set -euo pipefail

# Colores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Directorios
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROCESSING_DIR="$PROJECT_ROOT/services/processing-engine"

log() { echo -e "$1" >&2; }
log_info() { log "${BLUE}ℹ️  $1${NC}"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_error() { log "${RED}❌ $1${NC}"; }

show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║            🐳 DOCKER ECR UPDATE - DESARROLLO                 ║
║                                                              ║
║  Actualizar solo la imagen Docker del processing engine     ║
║  ⚡ Rápido - sin tocar infraestructura                      ║
║  🔄 Para cambios en código Python                           ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

validate_prerequisites() {
    log_info "Validando prerequisitos..."
    
    # Verificar herramientas
    local missing_tools=()
    for tool in "aws" "docker" "terraform"; do
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
    
    # Verificar Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker no está ejecutándose"
        log_info "Iniciar Docker Desktop"
        exit 1
    fi
    
    # Verificar directorio processing engine
    if [[ ! -f "$PROCESSING_DIR/Dockerfile" ]]; then
        log_error "Dockerfile no encontrado en: $PROCESSING_DIR"
        exit 1
    fi
    
    log_success "Todos los prerequisitos cumplidos"
}

get_terraform_outputs() {
    log_info "Obteniendo configuración desde Terraform..."
    
    cd "$SCRIPT_DIR/.."
    
    # Obtener outputs necesarios
    local region account_id
    region=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ -z "$account_id" ]]; then
        log_error "No se pudo obtener Account ID de AWS"
        exit 1
    fi
    
    # Variables globales
    REGION="$region"
    ACCOUNT_ID="$account_id"
    ECR_REPO_NAME="agrosynchro-processing-engine"
    ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"
    
    log_success "Configuración obtenida:"
    log_info "  Region: $REGION"
    log_info "  Account ID: $ACCOUNT_ID"
    log_info "  ECR URI: $ECR_URI"
}

verify_ecr_repository() {
    log_info "Verificando repositorio ECR..."
    
    if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
        log_error "Repositorio ECR '$ECR_REPO_NAME' no existe"
        log_info "Ejecutar primero el deployment completo: ./deploy.sh"
        exit 1
    fi
    
    log_success "Repositorio ECR verificado"
}

build_and_push_image() {
    log_info "Construyendo imagen Docker..."
    
    cd "$PROCESSING_DIR"
    
    # Build de la imagen
    local build_tag="$ECR_REPO_NAME:latest"
    if ! docker build --platform linux/amd64 -t "$build_tag" .; then
        log_error "Failed to build Docker image"
        exit 1
    fi
    
    log_success "Imagen construida exitosamente"
    
    # Login a ECR
    log_info "Autenticando con ECR..."
    if ! aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"; then
        log_error "Failed to authenticate with ECR"
        exit 1
    fi
    
    # Tag para ECR
    log_info "Tagueando imagen para ECR..."
    docker tag "$build_tag" "$ECR_URI:latest"
    
    # Push a ECR
    log_info "Pushing imagen a ECR..."
    if ! docker push "$ECR_URI:latest"; then
        log_error "Failed to push image to ECR"
        exit 1
    fi
    
    log_success "Imagen actualizada en ECR exitosamente"
}

trigger_fargate_update() {
    log_info "Forzando actualización de tareas Fargate..."
    
    # Encontrar el servicio Fargate
    local service_name cluster_name
    service_name="agrosynchro-processing-service"
    cluster_name="agrosynchro-cluster"
    
    # Verificar que el servicio existe
    if aws ecs describe-services --cluster "$cluster_name" --services "$service_name" --region "$REGION" >/dev/null 2>&1; then
        # Forzar nuevo deployment para usar imagen actualizada
        log_info "Actualizando servicio Fargate..."
        aws ecs update-service \
            --cluster "$cluster_name" \
            --service "$service_name" \
            --force-new-deployment \
            --region "$REGION" >/dev/null
        
        log_success "Fargate service actualizado - nuevas tareas usarán imagen actualizada"
        log_info "💡 Las tareas nuevas se crearán automáticamente en unos minutos"
    else
        log_warning "Servicio Fargate no encontrado - la imagen está actualizada en ECR"
    fi
}

main() {
    show_banner
    
    log_info "🚀 Iniciando actualización de Docker en ECR..."
    echo ""
    
    validate_prerequisites
    get_terraform_outputs
    verify_ecr_repository
    build_and_push_image
    trigger_fargate_update
    
    echo ""
    log_success "🎉 Actualización completada exitosamente!"
    echo ""
    log_info "📋 Próximos pasos:"
    log_info "   1. Las nuevas tareas Fargate usarán la imagen actualizada"
    log_info "   2. Verificar logs en CloudWatch si es necesario"
    log_info "   3. Monitorear procesamiento en SQS"
    
    echo ""
    log_info "💡 TIP: Para cambios en Lambdas usar: ./update-lambdas.sh"
}

# Ejecutar función principal
main "$@"
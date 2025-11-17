#!/usr/bin/env bash
# =============================================================================
# AGROSYNCHRO - DEPLOY SIMPLIFICADO
# =============================================================================
# Propósito: Deployment razonablemente robusto pero mantenible
# Entorno:   AWS Academy (cada alumno con su propia cuenta)
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURACIÓN Y CONSTANTES
# =============================================================================

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Directorios
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SERVICES_DIR="$PROJECT_ROOT/services"

# Tag usado para detectar recursos del proyecto en AWS
readonly PROJECT_TAG_KEY="Project"
readonly PROJECT_TAG_VALUE="agrosynchro"

# Flags
AUTO_APPROVE=false
SKIP_INIT=false
SKIP_FRONTEND=false
SKIP_PROCESSING=false
VERBOSE=false

# =============================================================================
# LOGGING Y ERRORES
# =============================================================================

log()         { echo -e "$1" >&2; }
log_info()    { log "${BLUE}ℹ️  $1${NC}"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_error()   { log "${RED}❌ $1${NC}"; }

log_debug() {
  if [[ "$VERBOSE" == "true" ]]; then
    log "🔍 $1"
  fi
}

on_error() {
  local exit_code=$?
  local line_no=$1
  log_error "El script falló en la línea $line_no (código $exit_code)"
}

trap 'on_error $LINENO' ERR

run() {
  log_debug "Ejecutando: $*"
  "$@"
}

show_banner() {
  cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║        🚀 AGROSYNCHRO DEPLOY (versión simple)        ║
║                                                      ║
║        ⚠️  MODO: SIEMPRE DESDE CERO                  ║
║        🧹 Destruye todo y redeploya                  ║
╚══════════════════════════════════════════════════════╝
EOF
}

# =============================================================================
# VALIDACIONES BÁSICAS
# =============================================================================

validate_dependencies() {
  log_info "Validando dependencias básicas..."

  local missing=()

  for tool in terraform aws jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if ((${#missing[@]} > 0)); then
    log_error "Faltan dependencias: ${missing[*]}"
    exit 1
  fi

  log_success "Dependencias básicas OK (terraform, aws, jq)"

  # El resto son opcionales, se avisa en cada fase
}

validate_aws_access() {
  log_info "Validando acceso a AWS..."

  local arn
  arn=$(aws sts get-caller-identity --query 'Arn' --output text)
  local region
  region=$(aws configure get region 2>/dev/null || echo "us-east-1")

  log_success "AWS OK. ARN: $arn, Región: $region"
}

validate_project_structure() {
  log_info "Validando estructura del proyecto..."

  local required_files=(
    "$TF_DIR/main.tf"
    "$TF_DIR/variables.tf"
    "$TF_DIR/outputs.tf"
  )

  local required_dirs=(
    "$TF_DIR/modules"
  )

  for f in "${required_files[@]}"; do
    if [[ ! -f "$f" ]]; then
      log_error "Falta archivo requerido: $f"
      exit 1
    fi
  done

  for d in "${required_dirs[@]}"; do
    if [[ ! -d "$d" ]]; then
      log_error "Falta directorio requerido: $d"
      exit 1
    fi
  done

  log_success "Estructura Terraform OK"
}

# =============================================================================
# BUILD FRONTEND / PROCESSING
# =============================================================================

build_frontend() {
  if [[ "$SKIP_FRONTEND" == "true" ]]; then
    log_info "Saltando frontend (--skip-frontend)"
    return 0
  fi

  local frontend_dir="$SERVICES_DIR/web-dashboard/frontend"

  if [[ ! -d "$frontend_dir" ]]; then
    log_warning "Frontend no encontrado en $frontend_dir, se omite"
    return 0
  fi

  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    log_warning "Node/npm no instalados. No se puede construir el frontend."
    return 0
  fi

  log_info "Construyendo frontend..."
  cd "$frontend_dir"

  if [[ ! -f package.json ]]; then
    log_warning "package.json no encontrado, se omite build de frontend"
    return 0
  fi

  run npm ci
  run npm run build

  log_success "Frontend compilado"
}

build_processing_engine() {
  if [[ "$SKIP_PROCESSING" == "true" ]]; then
    log_info "Saltando processing (--skip-processing)"
    return 0
  fi

  local pe_dir="$SERVICES_DIR/processing-engine"
  local ecr_script="$SCRIPT_DIR/update-docker-ecr.sh"

  if [[ ! -d "$pe_dir" ]]; then
    log_warning "Processing engine no encontrado en $pe_dir, se omite"
    return 0
  fi

  if [[ ! -x "$ecr_script" ]]; then
    log_warning "Script $ecr_script no encontrado o no ejecutable, se omite processing"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log_warning "Docker no instalado. No se puede construir processing engine."
    return 0
  fi

  log_info "Construyendo processing engine + push a ECR..."
  cd "$pe_dir"
  run "$ecr_script"
  log_success "Processing engine construido y subido a ECR"
}

# =============================================================================
# TERRAFORM
# =============================================================================

terraform_init() {
  if [[ "$SKIP_INIT" == "true" ]]; then
    log_info "Saltando terraform init (--skip-init)"
    return 0
  fi

  log_info "Inicializando Terraform..."
  cd "$TF_DIR"
  run terraform init -input=false
  log_success "terraform init OK"
}

terraform_plan() {
  log_info "Generando plan Terraform..."
  cd "$TF_DIR"

  local plan_file="tfplan"
  run terraform plan -out="$plan_file" -input=false
  log_success "Plan generado en $plan_file"

  if [[ "$VERBOSE" == "true" ]]; then
    log_info "Resumen del plan:"
    terraform show -no-color "$plan_file" | sed -n '1,40p' || true
  fi
}

terraform_apply() {
  log_info "Aplicando plan Terraform..."
  cd "$TF_DIR"

  local plan_file="tfplan"
  if [[ ! -f "$plan_file" ]]; then
    log_error "No se encuentra el archivo de plan $plan_file"
    exit 1
  fi

  local args=("-input=false")
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    args+=("-auto-approve")
  fi
  args+=("$plan_file")

  run terraform apply "${args[@]}"
  log_success "Infraestructura desplegada"
}

# =============================================================================
# DESTROY Y REDEPLOY DESDE CERO (ENFOQUE SIMPLE)
# =============================================================================

clean_and_reset() {
  log_info "🧹 MODO SIEMPRE LIMPIO: Eliminando infraestructura existente..."

  cd "$TF_DIR"

  # 1. Intentar destroy si hay state
  if [[ -f "terraform.tfstate" ]] && [[ -s "terraform.tfstate" ]]; then
    log_info "Destruyendo infraestructura existente con Terraform..."
    
    # Destroy con auto-approve (más seguro que manualmente)
    if run terraform destroy -auto-approve -input=false; then
      log_success "✅ Infraestructura destruida con Terraform"
    else
      log_warning "⚠️  Destroy falló, pero continuaremos (puede que no haya recursos)"
    fi
  else
    log_info "No hay state local, saltando destroy de Terraform"
  fi

  # 2. Limpiar archivos de state locales
  log_info "Limpiando state local..."
  rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl 2>/dev/null || true
  rm -rf .terraform/terraform.tfstate 2>/dev/null || true
  
  # 3. Limpiar planes anteriores
  rm -f tfplan tfplan-* 2>/dev/null || true

  log_success "✅ Limpieza completada → próximo deployment será completamente limpio"
}

# =============================================================================
# POST-DEPLOYMENT CONFIGURATION
# =============================================================================

configure_cognito_lambda_env() {
  log_info "Configurando variables de entorno de Lambda Cognito..."
  cd "$TF_DIR"
  
  # Obtener outputs de Terraform
  local cognito_domain client_id lambda_name frontend_url
  
  cognito_domain=$(terraform output -raw cognito_domain 2>/dev/null || true)
  client_id=$(terraform output -raw cognito_client_id 2>/dev/null || true)
  lambda_name=$(terraform output -raw lambda_cognito_callback_function_name 2>/dev/null || true)
  frontend_url=$(terraform output -raw frontend_website_url 2>/dev/null || true)
  
  if [[ -z "$cognito_domain" || -z "$client_id" || -z "$lambda_name" ]]; then
    log_warning "No se pudieron obtener todos los outputs necesarios para Cognito Lambda"
    log_info "  cognito_domain: ${cognito_domain:-MISSING}"
    log_info "  client_id: ${client_id:-MISSING}"  
    log_info "  lambda_name: ${lambda_name:-MISSING}"
    log_info "Saltando configuración de Lambda Cognito..."
    return 0
  fi
  
  log_info "Actualizando Lambda: $lambda_name"
  log_info "  Cognito Domain: $cognito_domain"
  log_info "  Client ID: ${client_id:0:8}..."
  log_info "  Frontend URL: $frontend_url"
  
  # Actualizar variables de entorno de Lambda
  if aws lambda update-function-configuration \
    --function-name "$lambda_name" \
    --environment "Variables={COGNITO_DOMAIN=$cognito_domain,CLIENT_ID=$client_id,FRONTEND_URL=$frontend_url}" \
    --output table --query 'Environment.Variables' >/dev/null 2>&1; then
    log_success "Variables de entorno de Lambda Cognito actualizadas correctamente"
  else
    log_error "Error actualizando variables de entorno de Lambda Cognito"
    return 1
  fi
}

# =============================================================================
# POST-DEPLOYMENT (resumen muy simple)
# =============================================================================

show_outputs_summary() {
  log_info "Mostrando outputs principales..."
  cd "$TF_DIR"

  if ! terraform output >/dev/null 2>&1; then
    log_warning "No se pudieron leer outputs de Terraform."
    return 0
  fi

  local outputs_json
  outputs_json=$(terraform output -json)

  local frontend_url api_url
  frontend_url=$(echo "$outputs_json" | jq -r '.frontend_website_url.value // empty' || true)
  api_url=$(echo "$outputs_json" | jq -r '.api_gateway_invoke_url.value // empty' || true)

  echo
  echo "════════════ RESUMEN DEPLOY ════════════"
  echo "Frontend : ${frontend_url:-No configurado}"
  echo "API      : ${api_url:-No configurada}"
  echo "════════════════════════════════════════"
  echo
}

# =============================================================================
# ARGUMENTOS
# =============================================================================

show_help() {
  cat << EOF
Uso: ./deploy.sh [opciones]

Opciones:
  -y, --auto-approve     Ejecutar terraform apply con -auto-approve
      --skip-init        No correr terraform init
      --skip-frontend    No construir el frontend
      --skip-processing  No construir el processing engine
  -v, --verbose          Más logs
  -h, --help             Mostrar esta ayuda
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--auto-approve)   AUTO_APPROVE=true; shift ;;
      --skip-init)         SKIP_INIT=true; shift ;;
      --skip-frontend)     SKIP_FRONTEND=true; shift ;;
      --skip-processing)   SKIP_PROCESSING=true; shift ;;
      -v|--verbose)        VERBOSE=true; shift ;;
      -h|--help)           show_help; exit 0 ;;
      *)
        log_error "Opción desconocida: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  show_banner
  parse_arguments "$@"

  log_info "Config:"
  log_info "  AUTO_APPROVE   = $AUTO_APPROVE"
  log_info "  SKIP_INIT      = $SKIP_INIT"
  log_info "  SKIP_FRONTEND  = $SKIP_FRONTEND"
  log_info "  SKIP_PROCESSING= $SKIP_PROCESSING"
  log_info "  VERBOSE        = $VERBOSE"
  echo

  validate_dependencies
  validate_aws_access
  validate_project_structure

  if [[ "$AUTO_APPROVE" == "false" ]]; then
    echo
    echo "⚠️  CONFIRMACIÓN REQUERIDA - MODO DESTRUCTIVO"
    echo ""
    echo "🧹 Este script va a:"
    echo "   1. DESTRUIR toda la infraestructura existente"
    echo "   2. LIMPIAR el state local"
    echo "   3. CREAR todo desde cero"
    echo ""
    echo "💰 Esto puede generar costos en AWS."
    echo "🕐 El proceso toma ~15-20 minutos."
    echo ""
    read -r -p "¿Confirmas DESTRUIR y RECREAR todo? (y/N): " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      log_info "Deployment cancelado por el usuario."
      exit 0
    fi
    echo ""
    log_warning "🚀 Iniciando deployment destructivo..."
    echo ""
  fi

  # Fase 1: build frontend
  build_frontend

  # Fase 2: terraform (siempre desde cero)
  clean_and_reset
  terraform_init
  terraform_plan
  terraform_apply

  # Fase 2.5: configurar Lambda Cognito post-deployment
  configure_cognito_lambda_env

  # Fase 3: processing engine (usa ECR creado por Terraform)
  build_processing_engine

  # Fase 4: resumen de outputs
  show_outputs_summary

  log_success "Deployment completado."
}

main "$@"

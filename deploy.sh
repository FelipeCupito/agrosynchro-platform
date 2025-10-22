#!/bin/bash

# =============================================================================
# AGROSYNCHRO COMPLETE DEPLOYMENT SCRIPT
# =============================================================================
# Automated deployment script that:
# 1. Validates AWS credentials and prerequisites
# 2. Initializes and plans Terraform infrastructure
# 3. Deploys infrastructure
# 4. Builds and pushes Docker image to ECR
# 5. Updates Fargate services with new image
# 6. Validates deployment and provides endpoints
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Project configuration
PROJECT_NAME="agrosynchro"
TERRAFORM_DIR="terraform"
SERVICE_DIR="services/processing-engine"
TFVARS_FILE="environments/aws/terraform.tfvars"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_banner() {
    echo -e "${CYAN}"
    echo "========================================================================"
    echo "  🚀 AGROSYNCHRO - AUTOMATED AWS DEPLOYMENT"
    echo "========================================================================"
    echo -e "${NC}"
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if running from project root
    if [ ! -f "terraform/main.tf" ] || [ ! -f "services/processing-engine/Dockerfile" ]; then
        log_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    log_info "Verifying AWS credentials..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    log_success "Prerequisites check completed"
    log_info "AWS Account: $AWS_ACCOUNT_ID"
    log_info "AWS Region: $AWS_REGION"
}

terraform_init_and_plan() {
    log_step "Initializing and planning Terraform..."
    
    cd $TERRAFORM_DIR
    
    # Initialize Terraform
    log_info "Running terraform init..."
    terraform init
    
    # Plan deployment
    log_info "Running terraform plan..."
    terraform plan -var-file="$TFVARS_FILE" -out=tfplan
    
    log_success "Terraform plan completed successfully"
    cd ..
}

deploy_infrastructure() {
    log_step "Deploying AWS infrastructure..."
    
    cd $TERRAFORM_DIR
    
    log_info "Applying Terraform configuration..."
    terraform apply -auto-approve tfplan
    
    log_success "Infrastructure deployed successfully"
    cd ..
}

run_database_migrations() {
    log_step "Database migrations will run automatically on Fargate startup..."
    log_info "✅ Migrations are now handled by the Processing Engine container"
    log_success "Migration step completed (automated)"
}

build_and_deploy_image() {
    log_step "Building and deploying Docker image..."
    
    cd $SERVICE_DIR
    
    log_info "Running build-and-deploy.sh..."
    chmod +x build-and-deploy.sh
    ./build-and-deploy.sh
    
    log_success "Docker image deployed to ECR successfully"
    cd ../..
}

update_fargate_services() {
    log_step "Updating Fargate services with new image..."
    
    cd $TERRAFORM_DIR
    
    log_info "Applying Terraform to update Fargate services..."
    terraform apply -auto-approve -var-file="$TFVARS_FILE"
    
    log_success "Fargate services updated successfully"
    cd ..
}

validate_deployment() {
    log_step "Validating deployment..."
    
    cd $TERRAFORM_DIR
    
    # Get API Gateway URL
    API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null)
    
    if [ -z "$API_URL" ]; then
        log_warning "Could not retrieve API Gateway URL from Terraform outputs"
        cd ..
        return
    fi
    
    log_info "API Gateway URL: $API_URL"
    
    # Test ping endpoint
    log_info "Testing ping endpoint..."
    if curl -s -f "$API_URL/ping" > /dev/null; then
        log_success "Ping endpoint is responding"
    else
        log_warning "Ping endpoint is not responding yet (may take a few minutes)"
    fi
    
    # Test SQS endpoint
    log_info "Testing SQS message endpoint..."
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/messages" \
        -H "Content-Type: application/json" \
        -d '{"message": "deployment test"}')
    
    if [ "$RESPONSE" = "200" ]; then
        log_success "SQS message endpoint is responding"
    else
        log_warning "SQS message endpoint returned status: $RESPONSE"
    fi
    
    cd ..
}

display_summary() {
    log_step "Deployment Summary"
    
    cd $TERRAFORM_DIR
    
    echo -e "${GREEN}"
    echo "========================================================================"
    echo "  ✅ DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "========================================================================"
    echo -e "${NC}"
    
    # Display key outputs
    API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")
    FRONTEND_URL=$(terraform output -raw frontend_website_url 2>/dev/null || echo "")
    COGNITO_DOMAIN=$(terraform output -raw cognito_domain 2>/dev/null || echo "")
    COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id 2>/dev/null || echo "")
    PROCESSED_BUCKET=$(terraform output -raw processed_images_bucket_name 2>/dev/null || echo "")
    RAW_BUCKET=$(terraform output -raw raw_images_bucket_name 2>/dev/null || echo "")
    SQS_URL=$(terraform output -raw sqs_queue_url 2>/dev/null || echo "")
    SQS_DLQ_URL=$(terraform output -raw sqs_dlq_url 2>/dev/null || echo "")
    RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
    RDS_DB_NAME=$(terraform output -raw rds_db_name 2>/dev/null || echo "")
    RDS_USER=$(terraform output -raw rds_username 2>/dev/null || echo "")
    
    echo -e "${CYAN}🌐 API Gateway URL:${NC}"
    if [ -n "$API_URL" ]; then
        echo "  $API_URL"
    else
        echo "  Could not retrieve API URL"
    fi
    
    echo -e "${CYAN}🖥️ Frontend (S3 Static Site):${NC}"
    if [ -n "$FRONTEND_URL" ]; then
        echo "  $FRONTEND_URL"
    else
        echo "  Frontend URL not available"
    fi
    
    echo -e "${CYAN}📋 Available Endpoints:${NC}"
    if [ -n "$API_URL" ]; then
        echo "  • Health check: GET $API_URL/ping"
        echo "  • Sensor ingest: POST $API_URL/messages"
        echo "  • Image upload: POST $API_URL/api/drones/image"
        echo "  • Image analysis: GET $API_URL/images/analysis"
        echo "  • Sensor data: GET $API_URL/sensor_data?user_id=<id>"
        echo "  • Parameters: POST/GET $API_URL/parameters"
        echo "  • Reports: GET/POST $API_URL/reports"
        echo "  • Cognito callback: GET $API_URL/callback"
    fi
    
    echo -e "${CYAN}🔐 Cognito Hosted UI:${NC}"
    if [ -n "$COGNITO_DOMAIN" ] && [ -n "$COGNITO_CLIENT_ID" ]; then
        echo "  • Hosted UI: https://$COGNITO_DOMAIN/login?client_id=$COGNITO_CLIENT_ID&response_type=code&scope=email+openid+profile&redirect_uri=${API_URL}/callback"
        echo "  • Domain: $COGNITO_DOMAIN"
        echo "  • Client ID: $COGNITO_CLIENT_ID"
    else
        echo "  Cognito outputs not available"
    fi
    
    echo -e "${CYAN}💾 Storage Buckets:${NC}"
    if [ -n "$RAW_BUCKET" ]; then
        echo "  • Raw images (cache): $RAW_BUCKET"
    else
        echo "  • Raw images bucket not available"
    fi
    if [ -n "$PROCESSED_BUCKET" ]; then
        echo "  • Processed images (archived): $PROCESSED_BUCKET"
    else
        echo "  • Processed images bucket not available"
    fi
    terraform output frontend_bucket_name 2>/dev/null | sed 's/^/  • Frontend bucket: /'
    
    echo -e "${CYAN}🔧 Infrastructure:${NC}"
    terraform output environment 2>/dev/null | sed 's/^/  • Environment: /'
    terraform output region 2>/dev/null | sed 's/^/  • Region: /'
    
    echo -e "${CYAN}📬 Messaging:${NC}"
    if [ -n "$SQS_URL" ]; then
        echo "  • Queue: $SQS_URL"
    else
        echo "  • Queue URL not available"
    fi
    if [ -n "$SQS_DLQ_URL" ]; then
        echo "  • DLQ: $SQS_DLQ_URL"
    else
        echo "  • DLQ URL not available"
    fi
    
    echo -e "${CYAN}🗄️ Database:${NC}"
    if [ -n "$RDS_ENDPOINT" ]; then
        echo "  • Endpoint: $RDS_ENDPOINT"
    else
        echo "  • Endpoint not available"
    fi
    if [ -n "$RDS_DB_NAME" ]; then
        echo "  • DB Name: $RDS_DB_NAME"
    fi
    if [ -n "$RDS_USER" ]; then
        echo "  • DB User: $RDS_USER"
    fi
    
    echo -e "${CYAN}📚 Next Steps:${NC}"
    echo "  • Ejecuta ./test-e2e.sh para validar todos los flujos"
    echo "  • Monitorea logs en CloudWatch (Lambdas y Fargate)"
    echo "  • Revisa métricas en SQS, RDS y S3"
    echo "  • Configura alertas/observabilidad según tu operación"
    
    echo -e "${YELLOW}⚠️  Remember:${NC}"
    echo "  • Resources are running in AWS and may incur costs"
    echo "  • Use 'terraform destroy' to clean up when done"
    
    cd ..
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up..."
    
    # Remove terraform plan file if it exists
    if [ -f "$TERRAFORM_DIR/tfplan" ]; then
        rm -f "$TERRAFORM_DIR/tfplan"
    fi
    
    log_info "You may want to check AWS Console for any partially created resources"
    log_info "Run 'terraform destroy -var-file=environments/aws/terraform.tfvars' to clean up if needed"
}

# Main execution
main() {
    print_banner
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    terraform_init_and_plan
    deploy_infrastructure
    run_database_migrations
    build_and_deploy_image
    update_fargate_services
    validate_deployment
    display_summary
    
    # Clean up temporary files
    if [ -f "$TERRAFORM_DIR/tfplan" ]; then
        rm -f "$TERRAFORM_DIR/tfplan"
    fi
    
    log_success "Deployment script completed successfully!"
}

# Run main function
main "$@"

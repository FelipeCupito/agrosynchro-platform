#!/bin/bash

# =============================================================================
# BUILD AND DEPLOY SCRIPT FOR PROCESSING ENGINE
# =============================================================================
# Builds Docker image and deploys to ECR (LocalStack or AWS)
# Usage: ./build-and-deploy.sh [local|aws]
# =============================================================================

set -e

ENVIRONMENT=${1:-local}
PROJECT_NAME="agrosynchro"
SERVICE_NAME="processing-engine"
IMAGE_NAME="${PROJECT_NAME}-${SERVICE_NAME}"

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

# =============================================================================
# Configuration based on environment
# =============================================================================

if [ "$ENVIRONMENT" = "local" ]; then
    log_info "Deploying to LocalStack environment"
    ECR_ENDPOINT="http://localhost:4566"
    ECR_REGISTRY="localhost:4566"
    AWS_REGION="us-east-1"
    REPOSITORY_NAME="${PROJECT_NAME}-${SERVICE_NAME}"
    IMAGE_TAG="${ECR_REGISTRY}/${REPOSITORY_NAME}:latest"
    
elif [ "$ENVIRONMENT" = "aws" ]; then
    log_info "Deploying to AWS environment"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Failed to get AWS Account ID. Make sure AWS CLI is configured."
        exit 1
    fi
    
    AWS_REGION=${AWS_REGION:-us-east-1}
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    REPOSITORY_NAME="${PROJECT_NAME}-${SERVICE_NAME}"
    IMAGE_TAG="${ECR_REGISTRY}/${REPOSITORY_NAME}:latest"
    
else
    log_error "Invalid environment. Use 'local' or 'aws'"
    echo "Usage: $0 [local|aws]"
    exit 1
fi

log_info "Configuration:"
log_info "  Environment: $ENVIRONMENT"
log_info "  Registry: $ECR_REGISTRY"
log_info "  Repository: $REPOSITORY_NAME"
log_info "  Image Tag: $IMAGE_TAG"

# =============================================================================
# Build Docker image
# =============================================================================

log_info "Building Docker image..."
docker build -t $IMAGE_NAME:latest .

if [ $? -eq 0 ]; then
    log_success "Docker image built successfully"
else
    log_error "Docker build failed"
    exit 1
fi

# Tag for ECR
docker tag $IMAGE_NAME:latest $IMAGE_TAG

# =============================================================================
# ECR Operations
# =============================================================================

if [ "$ENVIRONMENT" = "local" ]; then
    log_info "Setting up LocalStack ECR..."
    
    # Check if LocalStack is running
    if ! curl -s http://localhost:4566/_localstack/health > /dev/null; then
        log_error "LocalStack is not running. Please start it with: docker-compose up -d localstack"
        exit 1
    fi
    
    # Configure AWS CLI for LocalStack
    export AWS_ACCESS_KEY_ID=test
    export AWS_SECRET_ACCESS_KEY=test
    export AWS_DEFAULT_REGION=$AWS_REGION
    
    # Create ECR repository if it doesn't exist
    log_info "Creating ECR repository in LocalStack..."
    aws ecr create-repository \
        --repository-name $REPOSITORY_NAME \
        --endpoint-url $ECR_ENDPOINT \
        --region $AWS_REGION \
        2>/dev/null || log_warning "Repository may already exist"
    
    # LocalStack doesn't require Docker login for ECR
    log_info "Pushing image to LocalStack ECR..."
    
elif [ "$ENVIRONMENT" = "aws" ]; then
    log_info "Setting up AWS ECR..."
    
    # Create ECR repository if it doesn't exist
    log_info "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name $REPOSITORY_NAME \
        --region $AWS_REGION \
        2>/dev/null || log_warning "Repository may already exist"
    
    # Login to ECR
    log_info "Logging into AWS ECR..."
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin $ECR_REGISTRY
    
    if [ $? -ne 0 ]; then
        log_error "ECR login failed"
        exit 1
    fi
fi

# =============================================================================
# Push image
# =============================================================================

log_info "Pushing image to ECR..."
docker push $IMAGE_TAG

if [ $? -eq 0 ]; then
    log_success "Image pushed successfully to ECR"
else
    log_error "Image push failed"
    exit 1
fi

# =============================================================================
# Update ECS service (if running)
# =============================================================================

if [ "$ENVIRONMENT" = "aws" ]; then
    log_info "Checking for ECS service to update..."
    
    CLUSTER_NAME="${PROJECT_NAME}-cluster"
    SERVICE_NAME="${PROJECT_NAME}-${SERVICE_NAME}"
    
    # Check if ECS service exists
    aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].serviceName' \
        --output text 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_info "Updating ECS service..."
        aws ecs update-service \
            --cluster $CLUSTER_NAME \
            --service $SERVICE_NAME \
            --force-new-deployment \
            --region $AWS_REGION > /dev/null
        
        log_success "ECS service update initiated"
    else
        log_warning "ECS service not found. Deploy with Terraform first."
    fi
fi

# =============================================================================
# Cleanup
# =============================================================================

log_info "Cleaning up local images..."
docker rmi $IMAGE_NAME:latest || true

# =============================================================================
# Summary
# =============================================================================

log_success "Deployment completed successfully!"
echo ""
log_info "Summary:"
log_info "  Environment: $ENVIRONMENT"
log_info "  Image: $IMAGE_TAG"
log_info "  Registry: $ECR_REGISTRY"

if [ "$ENVIRONMENT" = "local" ]; then
    log_info ""
    log_info "Next steps for LocalStack:"
    log_info "  1. Apply Terraform: terraform apply -var-file=environments/local/terraform.tfvars"
    log_info "  2. Check Fargate service status in LocalStack"
elif [ "$ENVIRONMENT" = "aws" ]; then
    log_info ""
    log_info "Next steps for AWS:"
    log_info "  1. Apply Terraform: terraform apply -var-file=environments/aws/terraform.tfvars"
    log_info "  2. Monitor ECS service deployment"
fi

echo ""
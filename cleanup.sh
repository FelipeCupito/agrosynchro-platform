#!/bin/bash

# =============================================================================
# AGROSYNCHRO CLEANUP SCRIPT
# =============================================================================
# Safely destroys all AWS infrastructure and cleans up resources
# Usage: ./cleanup.sh [--force]
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TERRAFORM_DIR="terraform"
TFVARS_FILE="environments/aws/terraform.tfvars"
FORCE_MODE=false

if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

echo -e "${CYAN}"
echo "========================================================================"
echo "  🧹 AGROSYNCHRO - CLEANUP SCRIPT"
echo "========================================================================"
echo -e "${NC}"

warning_prompt() {
    if [ "$FORCE_MODE" = false ]; then
        echo -e "${RED}⚠️  WARNING: This will DESTROY all AWS resources!${NC}"
        echo -e "${YELLOW}Resources that will be deleted:${NC}"
        echo "  • VPC and all networking components"
        echo "  • RDS database (including data!)"
        echo "  • S3 buckets (including stored images!)"
        echo "  • Fargate services and tasks"
        echo "  • API Gateway"
        echo "  • Lambda functions"
        echo "  • SQS queues"
        echo "  • CloudWatch logs"
        echo
        echo -e "${YELLOW}💰 This will stop all AWS charges for this project${NC}"
        echo
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "❌ Cleanup cancelled"
            exit 0
        fi
    fi
}

cleanup_s3_buckets() {
    echo -e "${BLUE}🪣 Cleaning up S3 buckets...${NC}"
    
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    # Find all agrosynchro buckets
    BUCKETS=$(aws s3 ls | grep agrosynchro | awk '{print $3}')
    
    if [ -z "$BUCKETS" ]; then
        echo "ℹ️  No S3 buckets found"
        return
    fi
    
    for bucket in $BUCKETS; do
        echo "🗑️  Emptying bucket: $bucket"
        
        # Delete all object versions (handles versioned buckets)
        echo "  📋 Deleting all object versions..."
        aws s3api list-object-versions --bucket "$bucket" --output json --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
        jq -r '.[] | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Delete delete markers (for versioned buckets)
        echo "  🏷️  Deleting delete markers..."
        aws s3api list-object-versions --bucket "$bucket" --output json --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
        jq -r '.[] | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Alternative: Force delete all remaining objects with s3 rm
        echo "  🧹 Force removing any remaining objects..."
        aws s3 rm s3://"$bucket" --recursive --quiet || true
        
        echo "  ✅ Bucket $bucket emptied"
    done
}

cleanup_ecr_images() {
    echo -e "${BLUE}🐳 Cleaning up ECR images...${NC}"
    
    # Get repository name and region
    REPO_NAME="agrosynchro-processing-engine"
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION &>/dev/null; then
        echo "📦 Deleting ECR repository with force: $REPO_NAME (region: $AWS_REGION)"
        aws ecr delete-repository --repository-name $REPO_NAME --region $AWS_REGION --force || true
        echo "✅ ECR repository deleted"
    else
        echo "ℹ️  ECR repository not found (already deleted or never created)"
    fi
}

terraform_destroy() {
    echo -e "${BLUE}🏗️  Destroying Terraform infrastructure...${NC}"
    
    cd $TERRAFORM_DIR
    
    # Check if there's anything to destroy
    if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ]; then
        echo "ℹ️  No Terraform state found"
        cd ..
        return
    fi
    
    echo "📋 Planning destruction..."
    terraform plan -destroy -var-file="$TFVARS_FILE"
    
    echo "💥 Destroying infrastructure..."
    terraform destroy -auto-approve -var-file="$TFVARS_FILE"
    
    echo "🧹 Cleaning up Terraform files and directories..."
    
    # Remove state files
    rm -f terraform.tfstate*
    rm -f .terraform.lock.hcl
    
    # Remove plan files
    rm -f tfplan
    rm -f *.tfplan
    
    # Remove terraform directory
    rm -rf .terraform/
    
    # Remove any crash logs
    rm -f crash.log
    rm -f crash.*.log
    
    # Remove any backup files
    rm -f *.backup
    
    echo "📁 Listing remaining files..."
    ls -la
    
    cd ..
    echo "✅ Terraform cleanup completed"
}

cleanup_local_docker() {
    echo -e "${BLUE}🐋 Cleaning up local Docker images...${NC}"
    
    # Remove any leftover agrosynchro images
    if docker images | grep -q agrosynchro; then
        echo "🗑️  Removing local Docker images..."
        docker images | grep agrosynchro | awk '{print $3}' | xargs docker rmi -f 2>/dev/null || true
        echo "✅ Local Docker images cleaned"
    else
        echo "ℹ️  No local Docker images found"
    fi
}

verify_cleanup() {
    echo -e "${BLUE}🔍 Verifying cleanup...${NC}"
    
    # Check if any resources remain
    echo "Checking for remaining AWS resources..."
    
    # Check VPCs
    VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=agrosynchro" --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
    if [ ! -z "$VPCS" ]; then
        echo "⚠️  Warning: VPCs still exist: $VPCS"
    fi
    
    # Check ECR repositories
    REPOS=$(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `agrosynchro`)].repositoryName' --output text 2>/dev/null || echo "")
    if [ ! -z "$REPOS" ]; then
        echo "⚠️  Warning: ECR repositories still exist: $REPOS"
    fi
    
    # Check RDS instances
    DBS=$(aws rds describe-db-instances --query 'DBInstances[?starts_with(DBInstanceIdentifier, `agrosynchro`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
    if [ ! -z "$DBS" ]; then
        echo "⚠️  Warning: RDS instances still exist: $DBS"
    fi
    
    echo "✅ Cleanup verification completed"
}

display_summary() {
    echo -e "${GREEN}"
    echo "========================================================================"
    echo "  ✅ CLEANUP COMPLETED!"
    echo "========================================================================"
    echo -e "${NC}"
    
    echo -e "${GREEN}🎉 All AgroSynchro resources have been cleaned up${NC}"
    echo
    echo -e "${BLUE}What was removed:${NC}"
    echo "  ✅ All AWS infrastructure (VPC, RDS, S3, etc.)"
    echo "  ✅ ECR Docker images"
    echo "  ✅ Local Terraform state"
    echo "  ✅ Local Docker images"
    echo
    echo -e "${YELLOW}💰 AWS charges for this project have been stopped${NC}"
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "  • Check AWS Console to verify all resources are gone"
    echo "  • Review final AWS bill in a few days"
    echo "  • Archive or delete project files if no longer needed"
    echo
    echo -e "${CYAN}To redeploy in the future:${NC}"
    echo "  ./deploy.sh"
}

main() {
    # Check prerequisites
    if [ ! -f "terraform/main.tf" ]; then
        echo -e "${RED}❌ Error: Run this script from the project root directory${NC}"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ Error: AWS CLI not found${NC}"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ Error: Terraform not found${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ Error: jq not found. Please install jq first.${NC}"
        exit 1
    fi
    
    # Execute cleanup
    warning_prompt
    cleanup_s3_buckets  
    cleanup_ecr_images  
    terraform_destroy
    cleanup_local_docker
    verify_cleanup
    display_summary
    
    echo -e "${GREEN}🎯 Cleanup script completed successfully!${NC}"
}

main "$@"
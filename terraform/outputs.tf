# =============================================================================
# OUTPUTS - AGROSYNCHRO INFRASTRUCTURE
# =============================================================================

# =============================================================================
# NETWORKING OUTPUTS
# =============================================================================
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"  
  value       = module.networking.private_subnet_ids
}

# =============================================================================
# API GATEWAY OUTPUTS
# =============================================================================
output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL - Main entry point"
  value       = module.api_gateway.api_gateway_invoke_url
}

output "api_gateway_rest_api_id" {
  description = "API Gateway REST API ID"
  value       = module.api_gateway.api_gateway_rest_api_id
}

# =============================================================================
# SQS OUTPUTS
# =============================================================================
output "sqs_queue_url" {
  description = "SQS queue URL for messages"
  value       = module.sqs.queue_url
}

output "sqs_dlq_url" {
  description = "SQS dead letter queue URL"
  value       = module.sqs.dlq_url
}

# =============================================================================
# RDS OUTPUTS
# =============================================================================
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_db_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_username" {
  description = "RDS master username"
  value       = module.rds.db_username
}

# =============================================================================
# S3 OUTPUTS
# =============================================================================
output "raw_images_bucket_name" {
  description = "S3 bucket for raw images"
  value       = module.s3.raw_images_bucket_name
}

output "processed_images_bucket_name" {
  description = "S3 bucket for processed images"
  value       = module.s3.processed_images_bucket_name
}

output "frontend_bucket_name" {
  description = "S3 bucket for frontend static files"
  value       = module.s3.frontend_bucket_name
}

output "frontend_website_url" {
  description = "Frontend website URL"
  value       = "http://${module.s3.frontend_bucket_website_endpoint}"
}

# =============================================================================
# FARGATE OUTPUTS
# =============================================================================
# ALB outputs removed - functionality moved to API Gateway
# output "alb_dns_name" - REMOVED
# output "alb_health_check_url" - REMOVED

# =============================================================================
# ACCESS OUTPUTS
# =============================================================================
output "bastion_public_ip" {
  description = "Bastion host removed - using serverless architecture"
  value       = "N/A - Serverless architecture"
}

# =============================================================================
# ENVIRONMENT INFO
# =============================================================================
output "environment" {
  description = "Current environment"
  value       = "aws"
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

# =============================================================================
# QUICK START GUIDE
# =============================================================================
output "quick_start_info" {
  description = "Quick start information"
  value = <<-EOT
    
    🚀 AGROSYNCHRO INFRASTRUCTURE DEPLOYED
    =====================================
    
    Environment: aws
    Region: ${var.aws_region}
    
    🌐 Main API Endpoint:
    ${module.api_gateway.api_gateway_invoke_url}
    
    📋 Available endpoints:
    • Health check: GET ${module.api_gateway.api_gateway_invoke_url}/ping
    • Send message: POST ${module.api_gateway.api_gateway_invoke_url}/messages
    
    🔧 SQS Queue: ${module.sqs.queue_url}
    
    🚀 Serverless Architecture Deployed!
    
    📚 Next steps:
    1. Deploy containers to Fargate
    2. Deploy Fargate services
    3. Set up RDS database
    4. Configure S3 buckets
    
    EOT
}

# =============================================================================
# COGNITO OUTPUTS
# =============================================================================
output "cognito_domain" {
  description = "Cognito domain for Hosted UI"
  value       = module.cognito.domain
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.cognito.user_pool_client_id
}
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
  description = "Current Terraform workspace/environment"
  value       = terraform.workspace
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
    
    Environment: ${terraform.workspace}
    Region: ${var.aws_region}
    
    🌐 Main API Endpoint:
    ${module.api_gateway.api_gateway_invoke_url}
    
    📋 Available endpoints:
    • Health check: GET ${module.api_gateway.api_gateway_invoke_url}/ping
    • Send message: POST ${module.api_gateway.api_gateway_invoke_url}/messages
    
    🔧 SQS Queue: ${module.sqs.queue_url}
    
    🚀 Serverless Architecture Deployed!
    
    📚 Next steps:
    ${terraform.workspace == "local" ? "1. Make sure LocalStack is running" : "1. Deploy containers to Fargate"}
    2. Deploy Fargate services
    3. Set up RDS database
    4. Configure S3 buckets
    
    EOT
}
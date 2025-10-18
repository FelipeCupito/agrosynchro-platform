# =============================================================================
# TERRAFORM PROVIDERS CONFIGURATION
# =============================================================================
# Configuración para soportar múltiples environments:
# - local: Usa LocalStack para desarrollo
# - aws: Usa AWS real para producción
# =============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# =============================================================================
# AWS PROVIDER CONFIGURATION
# =============================================================================
# Configuración condicional basada en el workspace:
# - local: LocalStack endpoints 
# - aws: AWS real
provider "aws" {
  region = var.aws_region

  # Configuración para LocalStack (ambiente local)
  dynamic "endpoints" {
    for_each = terraform.workspace == "local" ? [1] : []
    content {
      apigateway      = "http://localhost:4566"
      cloudformation  = "http://localhost:4566"
      cloudwatch      = "http://localhost:4566"
      cloudwatchlogs  = "http://localhost:4566"
      dynamodb        = "http://localhost:4566"
      ec2             = "http://localhost:4566"
      ecs             = "http://localhost:4566"
      elasticache     = "http://localhost:4566"
      iam             = "http://localhost:4566"
      lambda          = "http://localhost:4566"
      rds             = "http://localhost:4566"
      s3              = "http://localhost:4566"
      secretsmanager  = "http://localhost:4566"
      sqs             = "http://localhost:4566"
      sts             = "http://localhost:4566"
    }
  }

  # Configuración específica para LocalStack
  access_key = terraform.workspace == "local" ? "test" : null
  secret_key = terraform.workspace == "local" ? "test" : null
  token      = terraform.workspace == "local" ? "test" : null
  
  # Skip validations para LocalStack
  skip_credentials_validation = terraform.workspace == "local" ? true : false
  skip_metadata_api_check     = terraform.workspace == "local" ? true : false
  skip_requesting_account_id  = terraform.workspace == "local" ? true : false
  skip_region_validation      = terraform.workspace == "local" ? true : false
  
  # Force path style para S3 en LocalStack
  s3_use_path_style = terraform.workspace == "local" ? true : false
  
  # Configuración común
  default_tags {
    tags = {
      Project     = "agrosynchro"
      Environment = terraform.workspace
      ManagedBy   = "terraform"
    }
  }
}
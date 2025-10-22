# =============================================================================
# TERRAFORM PROVIDERS CONFIGURATION
# =============================================================================
# AWS production deployment configuration
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
provider "aws" {
  region = var.aws_region
  

  default_tags {
    tags = {
      Project   = "agrosynchro"
      ManagedBy = "terraform"
    }
  }
}
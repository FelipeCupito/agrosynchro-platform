# =============================================================================
# AGROSYNCHRO INFRASTRUCTURE - MAIN CONFIGURATION
# =============================================================================
# Esta configuración implementa la nueva arquitectura basada en:
# - API Gateway (entrada principal)
# - SQS (procesamiento asíncrono) 
# - Fargate (contenedores sin servidor)
# - RDS con Read Replica
# - Múltiples buckets S3
# =============================================================================

# Local variables
locals {
  project_name = "agrosynchro"
  environment  = terraform.workspace
  region       = var.aws_region
  
  # Tags comunes para todos los recursos
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# NETWORKING MODULE
# =============================================================================
module "networking" {
  source = "./modules/networking"
  
  project_name         = local.project_name
  region              = local.region
  vpc_cidr            = var.vpc_cidr_block
  public_subnet_cidrs = [var.public_subnet_1_cidr, var.public_subnet_2_cidr]
  private_subnet_cidrs = [var.private_subnet_1_cidr, var.private_subnet_2_cidr]
  availability_zones  = ["${local.region}a", "${local.region}b"]
}

# =============================================================================
# SQS MODULE
# =============================================================================
module "sqs" {
  source = "./modules/sqs"
  
  project_name = local.project_name
}

# =============================================================================
# S3 MODULE
# =============================================================================
module "s3" {
  source = "./modules/s3"
  
  project_name = local.project_name
  environment  = local.environment
}

# =============================================================================
# LAMBDA MODULE
# =============================================================================
module "lambda" {
  source = "./modules/lambda"
  
  project_name              = local.project_name
  environment              = local.environment
  lambda_role_arn          = module.s3.lambda_s3_role_arn
  raw_images_bucket_name   = module.s3.raw_images_bucket_name
  # api_gateway_execution_arn = module.api_gateway.api_gateway_rest_api_execution_arn
  
  depends_on = [module.s3]
}

# =============================================================================
# API GATEWAY MODULE
# =============================================================================
module "api_gateway" {
  source = "./modules/api-gateway"
  
  project_name         = local.project_name
  region              = local.region
  stage_name          = local.environment
  sqs_queue_name      = module.sqs.queue_name
  sqs_queue_url       = module.sqs.queue_url
  api_gateway_role_arn = module.sqs.api_gateway_role_arn
  s3_bucket_name      = module.s3.raw_images_bucket_name
  lambda_invoke_arn   = module.lambda.lambda_invoke_arn
  
  depends_on = [module.sqs]
}

# =============================================================================
# PLACEHOLDER MODULES (A completar)
# =============================================================================

# TODO: Fargate Module
# module "fargate" {
#   source = "./modules/fargate"
#   
#   project_name        = local.project_name
#   vpc_id             = module.networking.vpc_id
#   private_subnet_ids = module.networking.private_subnet_ids
#   sqs_queue_url      = module.sqs.queue_url
#   fargate_role_arn   = module.sqs.fargate_role_arn
# }

# TODO: RDS Module  
# module "rds" {
#   source = "./modules/rds"
#   
#   project_name       = local.project_name
#   vpc_id            = module.networking.vpc_id
#   private_subnet_ids = module.networking.private_subnet_ids
#   db_username       = var.db_username
#   db_password       = var.db_password
# }

# TODO: S3 Module
# module "s3" {
#   source = "./modules/s3"
#   
#   project_name = local.project_name
#   vpc_id      = module.networking.vpc_id
# }

# =============================================================================
# TEMPORARY: Bastion Host (para acceso y debugging)
# =============================================================================
resource "aws_security_group" "bastion_sg" {
  name        = "${local.project_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-bastion-sg"
  })
}

resource "aws_instance" "bastion" {
  count = local.environment == "aws" ? 1 : 0
  
  ami                    = "ami-0583d8c7a9c35822c"  # Amazon Linux 2023
  instance_type          = "t3.micro"
  subnet_id              = module.networking.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = var.key_pair_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git aws-cli
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-bastion-host"
  })
}
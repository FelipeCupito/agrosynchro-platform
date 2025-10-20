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
  environment  = "aws"
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
  db_subnet_cidrs     = [var.db_subnet_1_cidr, var.db_subnet_2_cidr]
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
  api_gateway_execution_arn = module.api_gateway.api_gateway_rest_api_execution_arn
  
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

# =============================================================================
# FARGATE MODULE - AWS Real
# =============================================================================
module "fargate" {
  source = "./modules/fargate"
  
  project_name        = local.project_name
  aws_region         = local.region
  vpc_id             = module.networking.vpc_id
  vpc_cidr           = var.vpc_cidr_block
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  db_subnet_cidrs    = [var.db_subnet_1_cidr, var.db_subnet_2_cidr]
  
  # SQS integration
  sqs_queue_url      = module.sqs.queue_url
  sqs_queue_arn      = module.sqs.queue_arn
  
  # S3 integration
  raw_images_bucket_name      = module.s3.raw_images_bucket_name
  raw_images_bucket_arn       = module.s3.raw_images_bucket_arn
  processed_images_bucket_name = module.s3.processed_images_bucket_name
  processed_images_bucket_arn  = module.s3.processed_images_bucket_arn
  
  # RDS integration (extract hostname without port)
  rds_endpoint    = split(":", module.rds.db_instance_endpoint)[0]
  rds_db_name     = module.rds.db_name
  rds_username    = module.rds.db_username
  rds_password    = var.db_password
  
  depends_on = [module.sqs, module.s3, module.rds]
}

# =============================================================================
# RDS MODULE
# =============================================================================
module "rds" {
  source = "./modules/rds"
  
  project_name       = local.project_name
  vpc_id            = module.networking.vpc_id
  vpc_cidr          = var.vpc_cidr_block
  private_subnet_ids = module.networking.database_subnet_ids
  app_subnet_cidrs  = [var.private_subnet_1_cidr, var.private_subnet_2_cidr]
  db_username       = var.db_username
  db_password       = var.db_password
  
  # AWS settings
  db_instance_class = "db.t3.small"
  create_read_replica = var.create_read_replica
}

# S3 Module already implemented above

# =============================================================================
# BASTION HOST REMOVED - Not needed in serverless architecture
# =============================================================================
# Debugging ahora se hace con:
# - CloudWatch Logs para Lambda/Fargate
# - AWS Console para RDS/S3/SQS
# - AWS CLI local para testing
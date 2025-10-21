# =============================================================================
# AGROSYNCHRO INFRASTRUCTURE - MAIN CONFIGURATION
# =============================================================================

# Data sources
data "aws_caller_identity" "current" {}

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
  region                   = local.region
  lambda_role_arn          = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  raw_images_bucket_name   = module.s3.raw_images_bucket_name
  api_gateway_execution_arn = ""  # Optional - can be set later if needed
  
  # VPC configuration
  vpc_id           = module.networking.vpc_id
  private_subnets  = module.networking.private_subnet_ids
  
  # Database configuration
  db_host     = split(":", module.rds.db_instance_endpoint)[0]
  db_name     = module.rds.db_name
  db_user     = var.db_username
  db_password = var.db_password
  db_port     = tostring(module.rds.db_port)
  
  # Cognito configuration for callback Lambda
  # Dejar vacío para evitar ciclo de dependencias (Lambda -> Cognito -> API Gateway -> Lambda)
  # Actualizar manualmente después con: aws lambda update-function-configuration
  cognito_domain    = ""
  cognito_client_id = ""
  # Frontend S3 static website URL (S3 website endpoints are HTTP-only)
  frontend_url      = "http://${module.s3.frontend_bucket_name}.s3-website-${local.region}.amazonaws.com"
  
  depends_on = [module.s3, module.networking, module.rds]
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
  
  # API Lambda function invoke ARNs
  lambda_users_get_invoke_arn       = module.lambda.lambda_users_get_invoke_arn
  lambda_users_post_invoke_arn      = module.lambda.lambda_users_post_invoke_arn
  lambda_parameters_get_invoke_arn  = module.lambda.lambda_parameters_get_invoke_arn
  lambda_parameters_post_invoke_arn = module.lambda.lambda_parameters_post_invoke_arn
  lambda_sensor_data_get_invoke_arn = module.lambda.lambda_sensor_data_get_invoke_arn
  lambda_reports_get_invoke_arn     = module.lambda.lambda_reports_get_invoke_arn
  lambda_reports_post_invoke_arn    = module.lambda.lambda_reports_post_invoke_arn
  
  # API Lambda function ARNs for permissions
  lambda_users_get_function_arn       = module.lambda.lambda_users_get_function_arn
  lambda_users_post_function_arn      = module.lambda.lambda_users_post_function_arn
  lambda_parameters_get_function_arn  = module.lambda.lambda_parameters_get_function_arn
  lambda_parameters_post_function_arn = module.lambda.lambda_parameters_post_function_arn
  lambda_sensor_data_get_function_arn = module.lambda.lambda_sensor_data_get_function_arn
  lambda_reports_get_function_arn     = module.lambda.lambda_reports_get_function_arn
  lambda_reports_post_function_arn    = module.lambda.lambda_reports_post_function_arn
  
  # Cognito Callback Lambda
  lambda_cognito_callback_invoke_arn   = module.lambda.lambda_cognito_callback_invoke_arn
  lambda_cognito_callback_function_arn = module.lambda.lambda_cognito_callback_function_arn
  
  depends_on = [module.sqs, module.lambda]
}

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

# =============================================================================
# COGNITO MODULE - User Authentication
# =============================================================================

# Random string para hacer el dominio de Cognito único
resource "random_string" "cognito_domain" {
  length  = 6
  upper   = false
  special = false
}

module "cognito" {
  source = "./modules/cognito"
  
  project_name  = local.project_name
  domain_prefix = random_string.cognito_domain.result
  
  # URLs del callback permitidas por Cognito (HTTPS excepto localhost)
  callback_urls = [
    "http://localhost:3000/callback",
    "${module.api_gateway.api_gateway_invoke_url}/callback"
  ]
  
  # Logout URLs - Solo localhost por ahora (S3 website es HTTP y Cognito requiere HTTPS)
  # Para producción, usar CloudFront con HTTPS o un custom domain
  logout_urls = [
    "http://localhost:3000/"
  ]
  
  # OAuth flows para aplicaciones web
  oauth_flows  = ["code"]
  oauth_scopes = ["email", "openid", "profile"]
}

# =============================================================================
# FRONTEND CONFIGURATION - DYNAMIC ENV.JS WITH API GATEWAY URL
# =============================================================================

# Generate dynamic env.js file with the correct API Gateway URL
resource "aws_s3_object" "frontend_env_js" {
  bucket       = module.s3.frontend_bucket_name
  key          = "env.js"
  content      = <<EOF
window.ENV = {
  API_URL: "${module.api_gateway.api_gateway_invoke_url}",
  COGNITO_DOMAIN: "${module.cognito.domain}",
  COGNITO_CLIENT_ID: "${module.cognito.user_pool_client_id}",
  CALLBACK_URL: "${module.api_gateway.api_gateway_invoke_url}/callback"
};
EOF
  content_type = "application/javascript"
  etag         = md5("${module.api_gateway.api_gateway_invoke_url}-${module.cognito.domain}-${module.cognito.user_pool_client_id}")
  
  depends_on = [module.api_gateway, module.s3, module.cognito]
}

# =============================================================================
# SECURITY GROUP RULES FOR LAMBDA TO RDS COMMUNICATION
# =============================================================================

# Allow Lambda security group to access RDS on port 5432
resource "aws_security_group_rule" "lambda_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.lambda.lambda_security_group_id
  security_group_id        = module.rds.security_group_id
  description              = "Allow Lambda to access RDS PostgreSQL"
}
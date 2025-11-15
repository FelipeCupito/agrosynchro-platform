
data "aws_caller_identity" "current" {}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

data "aws_availability_zones" "available" {
  state = "available"
}
locals {
  project_name = "agrosynchro"
  environment  = "aws"
  region       = var.aws_region

  # Tags base comunes
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    CreatedAt   = formatdate("YYYY-MM-DD", timestamp())
  }

  # Definir componentes para usar con for_each
  infrastructure_components = {
    vpc = {
      name = "${local.project_name}-vpc"
      type = "networking"
    }
    lambda = {
      name = "${local.project_name}-lambda"
      type = "compute"
    }
    rds = {
      name = "${local.project_name}-database"
      type = "storage"
    }
    s3 = {
      name = "${local.project_name}-storage"
      type = "storage"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.project_name
  cidr = var.vpc_cidr_block

  azs              = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets   = [var.public_subnet_1_cidr, var.public_subnet_2_cidr]
  private_subnets  = [var.private_subnet_1_cidr, var.private_subnet_2_cidr]
  database_subnets = [var.db_subnet_1_cidr, var.db_subnet_2_cidr]

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true

  tags = local.common_tags

  public_subnet_tags = {
    Type = "Public"
  }

  private_subnet_tags = {
    Type = "Private"
  }

  database_subnet_tags = {
    Type = "Database"
  }
}

# =============================================================================
# VPC ENDPOINT - S3 Gateway Endpoint para acceso privado
# =============================================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    module.vpc.public_route_table_ids,
    module.vpc.private_route_table_ids
  )

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-s3-endpoint"
  })
}

module "sqs" {
  source = "./modules/sqs"

  project_name = local.project_name
  
  # Configure for sensor messages (backwards compatibility)
  queue_name_suffix = "messages-queue"
  dlq_name_suffix   = "messages-dlq"
  queue_purpose     = "sensor_messages"
  
  # Optional: Add environment-specific tags
  additional_tags = {
    Environment = local.environment
    Component   = "messaging"
  }
}

module "s3" {
  source = "./modules/s3"

  project_name = local.project_name
  environment  = local.environment
  
  # Configure buckets with backwards compatibility keys
  buckets = {
    frontend = {
      purpose               = "static_frontend"
      public_read          = true
      enable_website       = true
      enable_versioning    = false
      enable_encryption    = false
      lifecycle_rules      = []
      noncurrent_version_expiration_days = 0
    }
    raw-images = {
      purpose               = "drone_raw_images"
      public_read          = false
      enable_website       = false
      enable_versioning    = false
      enable_encryption    = true
      lifecycle_rules      = [
        {
          transition_days = 180
          storage_class  = "GLACIER"
        }
      ]
      noncurrent_version_expiration_days = 0
    }
    processed-images = {
      purpose               = "drone_processed_images"
      public_read          = false
      enable_website       = false
      enable_versioning    = true
      enable_encryption    = true
      lifecycle_rules      = [
        {
          transition_days = 30
          storage_class  = "STANDARD_IA"
        },
        {
          transition_days = 90
          storage_class  = "GLACIER"
        }
      ]
      noncurrent_version_expiration_days = 365
    }
  }
  
  # Frontend files configuration (backwards compatibility)
  frontend_files_path = "${path.root}/../services/web-dashboard/frontend/build"
  frontend_files_exclude = ["env.js"]
}

module "lambda" {
  source = "./modules/lambda"

  project_name                 = local.project_name
  environment                  = local.environment
  region                       = local.region
  lambda_role_arn              = data.aws_iam_role.lab_role.arn
  raw_images_bucket_name       = module.s3.raw_images_bucket_name
  processed_images_bucket_name = module.s3.processed_images_bucket_name
  api_gateway_execution_arn    = "" # Optional - can be set later if needed

  # VPC configuration
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets

  # Database configuration
  db_host     = split(":", module.rds.db_instance_endpoint)[0]
  db_name     = module.rds.db_instance_name
  db_user     = var.db_username
  db_password = var.db_password
  db_port     = tostring(module.rds.db_instance_port)

  cognito_domain    = ""
  cognito_client_id = ""
  frontend_url      = "http://${module.s3.frontend_bucket_name}.s3-website-${local.region}.amazonaws.com"

  depends_on = [module.s3, module.vpc, module.rds]
}

module "api_gateway" {
  source = "./modules/api-gateway"

  project_name         = local.project_name
  region               = local.region
  stage_name           = local.environment
  sqs_queue_name       = module.sqs.queue_name
  sqs_queue_url        = module.sqs.queue_url
  api_gateway_role_arn = module.sqs.api_gateway_role_arn
  s3_bucket_name       = module.s3.raw_images_bucket_name
  lambda_invoke_arn    = module.lambda.lambda_invoke_arn

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

module "fargate" {
  source = "./modules/fargate"

  project_name       = local.project_name
  aws_region         = local.region
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr_block
  private_subnet_ids = module.vpc.private_subnets
  db_subnet_cidrs    = [var.db_subnet_1_cidr, var.db_subnet_2_cidr]

  # SQS integration
  sqs_queue_url = module.sqs.queue_url
  sqs_queue_arn = module.sqs.queue_arn

  # S3 integration
  raw_images_bucket_name       = module.s3.raw_images_bucket_name
  raw_images_bucket_arn        = module.s3.raw_images_bucket_arn
  processed_images_bucket_name = module.s3.processed_images_bucket_name
  processed_images_bucket_arn  = module.s3.processed_images_bucket_arn

  # RDS integration (extract hostname without port)
  rds_endpoint = split(":", module.rds.db_instance_endpoint)[0]
  rds_db_name  = module.rds.db_instance_name
  rds_username = module.rds.db_instance_username
  rds_password = var.db_password

  depends_on = [module.sqs, module.s3, module.rds]
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.1.1"

  identifier = "${local.project_name}-postgres"

  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  db_name  = "agrosynchro"
  username = var.db_username
  password = var.db_password
  port     = 5432

  manage_master_user_password = false

  vpc_security_group_ids = [aws_security_group.rds.id]

  # Database subnet group
  db_subnet_group_name   = module.vpc.database_subnet_group
  create_db_subnet_group = false

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  create_monitoring_role = false
  monitoring_interval    = 0

  skip_final_snapshot = true
  deletion_protection = false

  tags = local.common_tags
}

# Security group for RDS (needed as external module doesn't create it)
resource "aws_security_group" "rds" {
  name_prefix = "${local.project_name}-rds-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_1_cidr, var.private_subnet_2_cidr]
    description = "PostgreSQL access from private subnets"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}


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

  callback_urls = [
    "http://localhost:3000/callback",
    "${module.api_gateway.api_gateway_invoke_url}/callback"
  ]

  logout_urls = [
    "http://localhost:3000/"
  ]

  oauth_flows  = ["code"]
  oauth_scopes = ["email", "openid", "profile"]
}

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

# Ejemplo de for_each para tracking de componentes
resource "null_resource" "component_tracker" {
  for_each = local.infrastructure_components

  triggers = {
    component_name = each.value.name
    component_type = each.value.type
    timestamp      = timestamp()
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "lambda_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.lambda.lambda_security_group_id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow Lambda to access RDS PostgreSQL"
}
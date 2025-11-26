variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (local, dev, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "lambda_role_arn" {
  description = "IAM role ARN for Lambda function"
  type        = string
}

variable "raw_images_bucket_name" {
  description = "Name of the S3 bucket for raw images (drone_image_upload)"
  type        = string
}

variable "processed_images_bucket_name" {
  description = "Name of the S3 bucket for processed images used by API Lambdas"
  type        = string
  default     = ""
}

variable "api_gateway_execution_arn" {
  description = "API Gateway execution ARN for Lambda permissions (leave empty to skip)"
  type        = string
  default     = ""
}

variable "lambda_timeout" {
  description = "Default Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Default Lambda function memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_runtime" {
  description = "Lambda runtime for all functions"
  type        = string
  default     = "python3.11"
}

variable "package_dir" {
  description = "Local folder with Lambda source (for multi-function zip)"
  type        = string
  default     = "../services/lambda"
}

# --- VPC / Subnets para Lambdas que acceden a RDS ---
variable "vpc_id" {
  description = "VPC ID for Lambda SG"
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs for Lambda VPC config"
  type        = list(string)
}

# --- Credenciales/Config de DB para Lambdas API ---
variable "db_host" {
  description = "Database host (endpoint)"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "sensordb"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Database port"
  type        = string
  default     = "5432"
}

# --- Overrides opcionales para una Lambda más pesada (report_field) ---
variable "report_field_timeout" {
  description = "Timeout override for report_field Lambda"
  type        = number
  default     = 30
}

variable "report_field_memory_size" {
  description = "Memory override for report_field Lambda (MB)"
  type        = number
  default     = 1024
}

# --- Variables para Cognito Callback Lambda ---
variable "cognito_domain" {
  description = "Cognito User Pool domain (e.g., mydomain.auth.us-east-1.amazoncognito.com)"
  type        = string
  default     = ""
}

variable "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
  default     = ""
}

variable "frontend_url" {
  description = "Frontend URL for OAuth redirect after token exchange"
  type        = string
  default     = ""
}

variable "api_key" {
  description = "API key for reports generation external service"
  type = string
  sensitive = true
}


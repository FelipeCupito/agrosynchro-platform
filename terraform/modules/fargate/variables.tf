variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Fargate tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "Database subnet CIDRs for security group access"
  type        = list(string)
}

variable "sqs_queue_url" {
  description = "SQS queue URL"
  type        = string
}

variable "sqs_queue_arn" {
  description = "SQS queue ARN"
  type        = string
}

variable "raw_images_bucket_name" {
  description = "Raw images S3 bucket name"
  type        = string
}

variable "raw_images_bucket_arn" {
  description = "Raw images S3 bucket ARN"
  type        = string
}

variable "processed_images_bucket_name" {
  description = "Processed images S3 bucket name"
  type        = string
}

variable "processed_images_bucket_arn" {
  description = "Processed images S3 bucket ARN"
  type        = string
}

variable "rds_endpoint" {
  description = "RDS endpoint"
  type        = string
}

variable "rds_db_name" {
  description = "RDS database name"
  type        = string
}

variable "rds_username" {
  description = "RDS username"
  type        = string
}

variable "rds_password" {
  description = "RDS password (direct for AWS Academy)"
  type        = string
  sensitive   = true
}

variable "fargate_cpu" {
  description = "Fargate CPU units"
  type        = number
  default     = 512
}

variable "fargate_memory" {
  description = "Fargate memory in MB"
  type        = number
  default     = 1024
}

variable "fargate_desired_count" {
  description = "Desired number of Fargate tasks"
  type        = number
  default     = 1
}

variable "fargate_min_capacity" {
  description = "Minimum number of Fargate tasks"
  type        = number
  default     = 1
}

variable "fargate_max_capacity" {
  description = "Maximum number of Fargate tasks"
  type        = number
  default     = 10
}
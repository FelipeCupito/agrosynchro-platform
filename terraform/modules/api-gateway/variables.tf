variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "dev"
}

variable "sqs_queue_name" {
  description = "SQS queue name for API Gateway integration"
  type        = string
}

variable "sqs_queue_url" {
  description = "SQS queue URL for API Gateway integration"
  type        = string
}

variable "api_gateway_role_arn" {
  description = "IAM role ARN for API Gateway to access SQS"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for drone images"
  type        = string
}

variable "sensor_queue_url" {
  description = "SQS queue URL for sensor data"
  type        = string
}

variable "drone_queue_url" {
  description = "SQS queue URL for drone data"
  type        = string
}
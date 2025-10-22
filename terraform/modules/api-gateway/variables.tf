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

variable "lambda_invoke_arn" {
  description = "Lambda function invoke ARN for drone image processing"
  type        = string
}

variable "lambda_function_arn" {
  description = "Lambda function ARN for drone image processing permissions"
  type        = string
}

variable "lambda_users_get_invoke_arn" {
  description = "Invoke ARN for GET /users"
  type        = string
}

variable "lambda_users_post_invoke_arn" {
  description = "Invoke ARN for POST /users"
  type        = string
}

variable "lambda_parameters_get_invoke_arn" {
  description = "Invoke ARN for GET /parameters"
  type        = string
}

variable "lambda_parameters_post_invoke_arn" {
  description = "Invoke ARN for POST /parameters"
  type        = string
}

variable "lambda_sensor_data_get_invoke_arn" {
  description = "Invoke ARN for GET /sensor_data"
  type        = string
}

variable "lambda_reports_get_invoke_arn" {
  description = "Invoke ARN for GET /reports"
  type        = string
}

variable "lambda_reports_post_invoke_arn" {
  description = "Invoke ARN for POST /reports"
  type        = string
}

# Function ARNs for Lambda permissions
variable "lambda_users_get_function_arn" {
  description = "Function ARN for GET /users"
  type        = string
}

variable "lambda_users_post_function_arn" {
  description = "Function ARN for POST /users"
  type        = string
}

variable "lambda_parameters_get_function_arn" {
  description = "Function ARN for GET /parameters"
  type        = string
}

variable "lambda_parameters_post_function_arn" {
  description = "Function ARN for POST /parameters"
  type        = string
}

variable "lambda_sensor_data_get_function_arn" {
  description = "Function ARN for GET /sensor_data"
  type        = string
}

variable "lambda_reports_get_function_arn" {
  description = "Function ARN for GET /reports"
  type        = string
}

variable "lambda_reports_post_function_arn" {
  description = "Function ARN for POST /reports"
  type        = string
}

variable "lambda_drone_images_get_invoke_arn" {
  description = "Invoke ARN for GET /images/analysis"
  type        = string
}

variable "lambda_drone_images_get_function_arn" {
  description = "Function ARN for GET /images/analysis"
  type        = string
}

# Cognito Callback Lambda
variable "lambda_cognito_callback_invoke_arn" {
  description = "Invoke ARN for Cognito callback"
  type        = string
}

variable "lambda_cognito_callback_function_arn" {
  description = "Function ARN for Cognito callback"
  type        = string
}

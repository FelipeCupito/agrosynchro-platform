# --- Lambda base (drone_image_upload) ---
output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.drone_image_upload.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.drone_image_upload.function_name
}

output "lambda_invoke_arn" {
  description = "ARN to invoke the Lambda function"
  value       = aws_lambda_function.drone_image_upload.invoke_arn
}

output "lambda_function_url" {
  description = "Lambda function URL for direct invocation"
  value       = aws_lambda_function_url.drone_image_upload_url.function_url
}

# --- Invoke ARNs de las Lambdas API (para conectar con API Gateway del otro módulo) ---
output "lambda_users_get_invoke_arn" {
  description = "Invoke ARN for GET /users"
  value       = aws_lambda_function.api.invoke_arn
}

output "lambda_users_post_invoke_arn" {
  description = "Invoke ARN for POST /users"
  value       = aws_lambda_function.users_post.invoke_arn
}

output "lambda_parameters_get_invoke_arn" {
  description = "Invoke ARN for GET /parameters"
  value       = aws_lambda_function.parameters_get.invoke_arn
}

output "lambda_parameters_post_invoke_arn" {
  description = "Invoke ARN for POST /parameters"
  value       = aws_lambda_function.parameters_post.invoke_arn
}

output "lambda_sensor_data_get_invoke_arn" {
  description = "Invoke ARN for GET /sensor_data"
  value       = aws_lambda_function.sensor_data_get.invoke_arn
}

output "lambda_reports_get_invoke_arn" {
  description = "Invoke ARN for GET /reports"
  value       = aws_lambda_function.reports_get.invoke_arn
}

output "lambda_reports_post_invoke_arn" {
  description = "Invoke ARN for POST /reports"
  value       = aws_lambda_function.report_field.invoke_arn
}

# --- Function ARNs de las Lambdas API (para permisos de API Gateway) ---
output "lambda_users_get_function_arn" {
  description = "Function ARN for GET /users"
  value       = aws_lambda_function.api.arn
}

output "lambda_users_post_function_arn" {
  description = "Function ARN for POST /users"
  value       = aws_lambda_function.users_post.arn
}

output "lambda_parameters_get_function_arn" {
  description = "Function ARN for GET /parameters"
  value       = aws_lambda_function.parameters_get.arn
}

output "lambda_parameters_post_function_arn" {
  description = "Function ARN for POST /parameters"
  value       = aws_lambda_function.parameters_post.arn
}

output "lambda_sensor_data_get_function_arn" {
  description = "Function ARN for GET /sensor_data"
  value       = aws_lambda_function.sensor_data_get.arn
}

output "lambda_reports_get_function_arn" {
  description = "Function ARN for GET /reports"
  value       = aws_lambda_function.reports_get.arn
}

output "lambda_reports_post_function_arn" {
  description = "Function ARN for POST /reports"
  value       = aws_lambda_function.report_field.arn
}

output "lambda_drone_images_get_invoke_arn" {
  description = "Invoke ARN for GET /images/analysis"
  value       = aws_lambda_function.drone_images_get.invoke_arn
}

output "lambda_drone_images_get_function_arn" {
  description = "Function ARN for GET /images/analysis"
  value       = aws_lambda_function.drone_images_get.arn
}

# --- Database initialization function (comentado: descomentar cuando RDS esté listo) ---
# output "lambda_init_db_function_arn" {
#   description = "Function ARN for database initialization"
#   value       = aws_lambda_function.init_db.arn
# }

# output "lambda_init_db_function_name" {
#   description = "Function name for database initialization"
#   value       = aws_lambda_function.init_db.function_name
# }

# --- Info útil adicional ---
output "lambda_security_group_id" {
  description = "Security group ID used by API Lambdas"
  value       = aws_security_group.lambda_sg.id
}

# --- Cognito Callback Lambda ---
output "lambda_cognito_callback_invoke_arn" {
  description = "Invoke ARN for Cognito callback"
  value       = aws_lambda_function.cognito_callback.invoke_arn
}

output "lambda_cognito_callback_function_arn" {
  description = "Function ARN for Cognito callback"
  value       = aws_lambda_function.cognito_callback.arn
}

output "lambda_cognito_callback_function_name" {
  description = "Function name for Cognito callback"
  value       = aws_lambda_function.cognito_callback.function_name
}

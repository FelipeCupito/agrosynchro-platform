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
  value       = aws_lambda_function.drone_image_upload.qualified_arn
}
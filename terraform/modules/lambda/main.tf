# =============================================================================
# LAMBDA MODULE - DRONE IMAGE UPLOAD
# =============================================================================
# Lambda function para procesar uploads de imágenes de drones
# Recibe multipart/form-data desde API Gateway y sube a S3
# =============================================================================

# Archive file para el código de la Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.root}/../services/iot-gateway/lambda_upload.py"
  output_path = "${path.module}/lambda_function.zip"
}

# =============================================================================
# DEAD LETTER QUEUE
# =============================================================================

resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "${var.project_name}-lambda-dlq"
  message_retention_seconds  = 1209600  # 14 days
  
  tags = {
    Name = "${var.project_name}-lambda-dlq"
  }
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-drone-image-upload"
  retention_in_days = 14
  
  tags = {
    Name = "${var.project_name}-lambda-logs"
  }
}

# =============================================================================
# LAMBDA FUNCTION
# =============================================================================

resource "aws_lambda_function" "drone_image_upload" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-drone-image-upload"
  role            = var.lambda_role_arn
  handler         = "lambda_upload.handler"
  runtime         = "python3.11"
  timeout         = 60
  memory_size     = 512
  
  # Dead letter queue for error handling
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      RAW_IMAGES_BUCKET = var.raw_images_bucket_name
      PROJECT_NAME      = var.project_name
      ENVIRONMENT       = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-drone-image-upload"
    Purpose     = "drone_image_processing"
    Environment = var.environment
  }
}

# =============================================================================
# LAMBDA PERMISSIONS
# =============================================================================

# Permission para API Gateway invocar la Lambda
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drone_image_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}


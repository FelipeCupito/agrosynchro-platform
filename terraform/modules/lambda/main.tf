# =============================================================================
# LAMBDA BASE: drone_image_upload (se mantiene tu empaquetado puntual)
# =============================================================================

data "archive_file" "lambda_upload_zip" {
  type        = "zip"
  source_file = "${path.root}/../services/iot-gateway/lambda_upload.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Dead-letter queue
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${var.project_name}-lambda-dlq"
  message_retention_seconds = 1209600  # 14 days

  tags = { Name = "${var.project_name}-lambda-dlq" }
}

# Log group para drone_image_upload
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-drone-image-upload"
  retention_in_days = 14
  tags = { Name = "${var.project_name}-lambda-logs" }
}

# Lambda: drone_image_upload
resource "aws_lambda_function" "drone_image_upload" {
  filename         = data.archive_file.lambda_upload_zip.output_path
  function_name    = "${var.project_name}-drone-image-upload"
  role             = var.lambda_role_arn
  handler          = "lambda_upload.handler"
  runtime          = var.lambda_runtime
  timeout          = 60
  memory_size      = 512

  dead_letter_config { target_arn = aws_sqs_queue.lambda_dlq.arn }

  source_code_hash = data.archive_file.lambda_upload_zip.output_base64sha256

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

# (Opcional pero correcto) Function URL para la Lambda base
resource "aws_lambda_function_url" "drone_image_upload_url" {
  function_name      = aws_lambda_function.drone_image_upload.arn
  authorization_type = "NONE"
}

# Permiso para que API Gateway invoque la Lambda base (si se provee execution_arn)
resource "aws_lambda_permission" "api_gateway_invoke_drone_image_upload" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowAPIGatewayInvokeDroneImageUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drone_image_upload.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

# =============================================================================
# LAMBDAS ADICIONALES (API, users_post, parameters_get/post, sensor_data_get, report_field, reports_get)
# Empaquetadas desde un directorio (multi-función)
# =============================================================================

# Zip del directorio con todas las funciones
data "archive_file" "lambda_app_zip" {
  type        = "zip"
  source_dir  = var.package_dir
  output_path = "${path.module}/lambda.zip"
}

# SG para Lambdas en VPC
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda to access RDS"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-lambda-sg" }
}

# --- Helper locals para ENV comunes ---
locals {
  common_env = {
    DB_HOST       = var.db_host
    DB_NAME       = var.db_name
    DB_USER       = var.db_user
    DB_PASSWORD   = var.db_password
    DB_PORT       = var.db_port
    IMAGES_BUCKET = var.images_bucket_name
    REGION        = var.region
  }
}

# Lambda: api
resource "aws_lambda_function" "api" {
  function_name    = "${var.project_name}-api"
  role             = var.lambda_role_arn

  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256

  handler          = "app.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: users_post
resource "aws_lambda_function" "users_post" {
  function_name    = "${var.project_name}-users-post"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "users_post.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: parameters_get
resource "aws_lambda_function" "parameters_get" {
  function_name    = "${var.project_name}-parameters-get"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "parameters_get.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: parameters_post
resource "aws_lambda_function" "parameters_post" {
  function_name    = "${var.project_name}-parameters-post"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "parameters_post.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: sensor_data_get
resource "aws_lambda_function" "sensor_data_get" {
  function_name    = "${var.project_name}-sensor-data-get"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "sensor_data_get.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: report_field (más pesada)
resource "aws_lambda_function" "report_field" {
  function_name    = "${var.project_name}-report-field"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "report_field.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.report_field_timeout
  memory_size      = var.report_field_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: reports_get
resource "aws_lambda_function" "reports_get" {
  function_name    = "${var.project_name}-reports-get"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "reports_get.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# Lambda: init_db - Database initialization
resource "aws_lambda_function" "init_db" {
  function_name    = "${var.project_name}-init-db"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_app_zip.output_path
  source_code_hash = data.archive_file.lambda_app_zip.output_base64sha256
  handler          = "init_db.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = 60  # Longer timeout for database operations
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment { variables = local.common_env }
}

# =============================================================================
# Permisos para API Gateway -> Lambdas nuevas (dependen de var.api_gateway_execution_arn)
# =============================================================================

resource "aws_lambda_permission" "apigw_lambda" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewayApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_users_post" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewayUsersPost"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users_post.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_parameters_get" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewayParametersGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parameters_get.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_parameters_post" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewayParametersPost"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parameters_post.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_sensor_data_get" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewaySensorDataGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sensor_data_get.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_report_field" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewayReportField"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_field.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_reports_get" {
  count         = var.api_gateway_execution_arn == "" ? 0 : 1
  statement_id  = "AllowExecutionFromAPIGatewayReportsGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reports_get.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

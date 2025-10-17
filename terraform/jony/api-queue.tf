variable "region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-east-1"
}

provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"

  endpoints {
    apigateway   = "http://localhost:4566"
    iam          = "http://localhost:4566"
    sts          = "http://localhost:4566"
    sqs          = "http://localhost:4566"
  }

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# Crear una API Gateway REST
resource "aws_api_gateway_rest_api" "test_api" {
  name        = "local-test-api"
  description = "API Gateway REST API para pruebas locales"
}

# Obtener el recurso raíz
data "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  path        = "/"
}

# Crear un recurso /ping
resource "aws_api_gateway_resource" "ping" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "ping"
}

# Crear método GET para /ping
resource "aws_api_gateway_method" "get_ping" {
  rest_api_id   = aws_api_gateway_rest_api.test_api.id
  resource_id   = aws_api_gateway_resource.ping.id
  http_method   = "GET"
  authorization = "NONE"
}

# Crear integración MOCK para GET /ping
resource "aws_api_gateway_integration" "mock_get_ping" {
  rest_api_id             = aws_api_gateway_rest_api.test_api.id
  resource_id             = aws_api_gateway_resource.ping.id
  http_method             = aws_api_gateway_method.get_ping.http_method
  type                    = "MOCK"
  request_templates       = {
    "application/json" = "{\"statusCode\": 200}"
  }
  integration_http_method = "GET"
}

# Crear método de respuesta para GET /ping
resource "aws_api_gateway_method_response" "method_response_200" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.get_ping.http_method
  status_code = "200"
}

# Crear respuesta de integración para GET /ping
resource "aws_api_gateway_integration_response" "integration_response_200" {
  depends_on = [
    aws_api_gateway_integration.mock_get_ping
  ]

  rest_api_id = aws_api_gateway_rest_api.test_api.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.get_ping.http_method
  status_code = aws_api_gateway_method_response.method_response_200.status_code

  response_templates = {
    "application/json" = "{\"message\": \"pong\"}"
  }
}

# Crear la cola SQS "messages-queue"
resource "aws_sqs_queue" "messages_queue" {
  name = "messages-queue"
}

# Crear un recurso /messages
resource "aws_api_gateway_resource" "messages" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "messages"
}

# Crear método POST para /messages
resource "aws_api_gateway_method" "post_messages" {
  rest_api_id   = aws_api_gateway_rest_api.test_api.id
  resource_id   = aws_api_gateway_resource.messages.id
  http_method   = "POST"
  authorization = "NONE"
}

# Crear integración AWS para POST /messages apuntando a SQS
resource "aws_api_gateway_integration" "sqs_post_messages" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.post_messages.http_method
  type        = "AWS"
  integration_http_method = "POST"
  uri         = "arn:aws:apigateway:${var.region}:sqs:path/000000000000/${aws_sqs_queue.messages_queue.name}"
  credentials             = "arn:aws:iam::000000000000:role/apigateway_sqs_role"

  request_templates = {
    "application/json" = <<EOF
{
  "Action": "SendMessage",
  "MessageBody": "$util.escapeJavaScript($input.body)",
  "Version": "2012-11-05"
}
EOF
  }
}

# Crear método de respuesta para POST /messages
resource "aws_api_gateway_method_response" "post_messages_200" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.post_messages.http_method
  status_code = "200"
}

# Crear respuesta de integración para POST /messages
resource "aws_api_gateway_integration_response" "post_messages_200" {
  depends_on = [
    aws_api_gateway_integration.sqs_post_messages
  ]

  rest_api_id = aws_api_gateway_rest_api.test_api.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.post_messages.http_method
  status_code = aws_api_gateway_method_response.post_messages_200.status_code

  response_templates = {
    "application/json" = "{\"message\": \"Message sent to queue\"}"
  }
}

# Deployment para la API
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.mock_get_ping,
    aws_api_gateway_integration.sqs_post_messages
  ]
  rest_api_id = aws_api_gateway_rest_api.test_api.id
}

# Crear un stage llamado "test"
resource "aws_api_gateway_stage" "test_stage" {
  rest_api_id  = aws_api_gateway_rest_api.test_api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name   = "test"
}

# Output con la URL base de invocación
output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.test_api.id}.execute-api.us-east-1.amazonaws.com/${aws_api_gateway_stage.test_stage.stage_name}"
}
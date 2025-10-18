# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-api-gateway"
  }
}

# Get root resource
data "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  path        = "/"
}

# Health check resource /ping
resource "aws_api_gateway_resource" "ping" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "ping"
}

# GET method for /ping
resource "aws_api_gateway_method" "ping_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.ping.id
  http_method   = "GET"
  authorization = "NONE"
}

# Mock integration for /ping
resource "aws_api_gateway_integration" "ping_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.ping_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response for /ping
resource "aws_api_gateway_method_response" "ping_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.ping_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response for /ping
resource "aws_api_gateway_integration_response" "ping_integration_response" {
  depends_on = [aws_api_gateway_integration.ping_integration]

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.ping_get.http_method
  status_code = aws_api_gateway_method_response.ping_200.status_code

  response_templates = {
    "application/json" = "{\"message\": \"pong\", \"timestamp\": \"$context.requestTime\"}"
  }
}

# Messages resource /messages
resource "aws_api_gateway_resource" "messages" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "messages"
}

# POST method for /messages
resource "aws_api_gateway_method" "messages_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.messages.id
  http_method   = "POST"
  authorization = "NONE"
}

# SQS integration for /messages
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.messages_post.http_method
  type        = "AWS"
  
  integration_http_method = "POST"
  uri                    = "arn:aws:apigateway:${var.region}:sqs:path/${var.sqs_queue_name}"
  credentials            = var.api_gateway_role_arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-amz-json-1.0'"
  }

  request_templates = {
    "application/json" = <<EOF
{
  "Action": "SendMessage",
  "MessageBody": "$util.escapeJavaScript($input.body)",
  "QueueUrl": "${var.sqs_queue_url}"
}
EOF
  }
}

# Method response for /messages
resource "aws_api_gateway_method_response" "messages_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.messages_post.http_method
  status_code = "200"
}

# Integration response for /messages
resource "aws_api_gateway_integration_response" "sqs_integration_response" {
  depends_on = [aws_api_gateway_integration.sqs_integration]

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.messages_post.http_method
  status_code = aws_api_gateway_method_response.messages_200.status_code

  response_templates = {
    "application/json" = "{\"message\": \"Message sent to queue successfully\"}"
  }
}

# Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.ping_integration,
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration.drone_image_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.ping.id,
      aws_api_gateway_method.ping_get.id,
      aws_api_gateway_integration.ping_integration.id,
      aws_api_gateway_resource.messages.id,
      aws_api_gateway_method.messages_post.id,
      aws_api_gateway_integration.sqs_integration.id,
      aws_api_gateway_resource.drone_image.id,
      aws_api_gateway_method.drone_image_post.id,
      aws_api_gateway_integration.drone_image_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# DRONE ENDPOINTS
# =============================================================================

# /api resource
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "api"
}

# /api/drones resource
resource "aws_api_gateway_resource" "drones" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "drones"
}

# /api/drones/image resource
resource "aws_api_gateway_resource" "drone_image" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.drones.id
  path_part   = "image"
}

# POST method for /api/drones/image
resource "aws_api_gateway_method" "drone_image_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.drone_image.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integration for drone images
resource "aws_api_gateway_integration" "drone_image_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.drone_image.id
  http_method = aws_api_gateway_method.drone_image_post.http_method
  type        = "AWS_PROXY"
  
  integration_http_method = "POST"
  uri                    = var.lambda_invoke_arn
}

# Note: Con AWS_PROXY integration, Lambda maneja las respuestas directamente


# =============================================================================
# UPDATED DEPLOYMENT
# =============================================================================

# Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.stage_name

  tags = {
    Name = "${var.project_name}-${var.stage_name}"
  }
}
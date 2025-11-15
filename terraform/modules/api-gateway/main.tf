# Get current AWS account ID
data "aws_caller_identity" "current" {}

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

# ----------------------------------------
# Health check resource /ping
# ----------------------------------------
resource "aws_api_gateway_resource" "ping" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "ping"
}

resource "aws_api_gateway_method" "ping_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.ping.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "ping_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.ping_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "ping_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.ping.id
  http_method = aws_api_gateway_method.ping_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

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

# ----------------------------------------
# Messages resource /messages -> SQS
# ----------------------------------------
resource "aws_api_gateway_resource" "messages" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "messages"
}

resource "aws_api_gateway_method" "messages_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.messages.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.messages_post.http_method
  type        = "AWS"

  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${var.sqs_queue_name}"
  credentials             = var.api_gateway_role_arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage&MessageBody=$util.urlEncode($input.body)&QueueUrl=${var.sqs_queue_url}
EOF
  }
}

resource "aws_api_gateway_method_response" "messages_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.messages.id
  http_method = aws_api_gateway_method.messages_post.http_method
  status_code = "200"
}

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

# ----------------------------------------
# DRONE ENDPOINTS: /api/drones/image -> Lambda (proxy)
# ----------------------------------------
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "drones" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "drones"
}

resource "aws_api_gateway_resource" "drone_image" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.drones.id
  path_part   = "image"
}

resource "aws_api_gateway_method" "drone_image_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.drone_image.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "drone_image_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.drone_image.id
  http_method = aws_api_gateway_method.drone_image_post.http_method
  type        = "AWS_PROXY"

  integration_http_method = "POST"
  uri                     = var.lambda_invoke_arn
}

# /users
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "users"
}

resource "aws_api_gateway_method" "get_users" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "post_users" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "users_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_get_users" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.get_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_users_get_invoke_arn
}

resource "aws_api_gateway_integration" "lambda_post_users" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.post_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_users_post_invoke_arn
}

resource "aws_api_gateway_integration" "users_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

# CORS method responses for /users (documentar headers)
resource "aws_api_gateway_method_response" "users_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "get_users_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_users.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "post_users_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "post_users_response_201" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = "201"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

# OPTIONS integration response (poner headers CORS)
resource "aws_api_gateway_integration_response" "users_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  status_code = aws_api_gateway_method_response.users_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS,POST'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

# /parameters
resource "aws_api_gateway_resource" "parameters" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "parameters"
}

resource "aws_api_gateway_method" "get_parameters" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.parameters.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "post_parameters" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.parameters.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "parameters_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.parameters.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_get_parameters" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.parameters.id
  http_method             = aws_api_gateway_method.get_parameters.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_parameters_get_invoke_arn
}

resource "aws_api_gateway_integration" "lambda_post_parameters" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.parameters.id
  http_method             = aws_api_gateway_method.post_parameters.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_parameters_post_invoke_arn
}

resource "aws_api_gateway_integration" "parameters_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.parameters.id
  http_method = aws_api_gateway_method.parameters_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "parameters_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.parameters.id
  http_method = aws_api_gateway_method.parameters_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "post_parameters_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.parameters.id
  http_method = aws_api_gateway_method.post_parameters.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "parameters_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.parameters.id
  http_method = aws_api_gateway_method.parameters_options.http_method
  status_code = aws_api_gateway_method_response.parameters_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS,POST'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

# /sensor_data
resource "aws_api_gateway_resource" "sensor_data" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "sensor_data"
}

resource "aws_api_gateway_method" "get_sensor_data" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.sensor_data.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "sensor_data_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.sensor_data.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_get_sensor_data" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.sensor_data.id
  http_method             = aws_api_gateway_method.get_sensor_data.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_sensor_data_get_invoke_arn
}

resource "aws_api_gateway_integration" "sensor_data_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.sensor_data.id
  http_method = aws_api_gateway_method.sensor_data_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "sensor_data_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.sensor_data.id
  http_method = aws_api_gateway_method.sensor_data_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "get_sensor_data_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.sensor_data.id
  http_method = aws_api_gateway_method.get_sensor_data.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

# OPTIONS integration response (poner headers CORS)
resource "aws_api_gateway_integration_response" "sensor_data_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.sensor_data.id
  http_method = aws_api_gateway_method.sensor_data_options.http_method
  status_code = aws_api_gateway_method_response.sensor_data_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

# /images
resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "images"
}

resource "aws_api_gateway_method" "get_images" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.images.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "images_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.images.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_get_images" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.images.id
  http_method             = aws_api_gateway_method.get_images.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_get_images_invoke_arn
}

resource "aws_api_gateway_integration" "images_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.images_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "images_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.images_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "get_images_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.get_images.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "images_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.images_options.http_method
  status_code = aws_api_gateway_method_response.images_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

# /reports
resource "aws_api_gateway_resource" "reports" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "reports"
}

resource "aws_api_gateway_method" "get_reports" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.reports.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "post_reports" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.reports.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "reports_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.reports.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_get_reports" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.reports.id
  http_method             = aws_api_gateway_method.get_reports.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_reports_get_invoke_arn
}

resource "aws_api_gateway_integration" "lambda_post_reports" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.reports.id
  http_method             = aws_api_gateway_method.post_reports.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_reports_post_invoke_arn
}

resource "aws_api_gateway_integration" "reports_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.reports_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "reports_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.reports_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "get_reports_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.get_reports.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_method_response" "post_reports_response_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.post_reports.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }
}

resource "aws_api_gateway_integration_response" "reports_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.reports_options.http_method
  status_code = aws_api_gateway_method_response.reports_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS,POST'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

# ----------------------------------------
# Lambda permissions (usar function ARN como function_name)
# ----------------------------------------
resource "aws_lambda_permission" "apigw_invoke_users_get" {
  statement_id  = "AllowAPIGatewayInvokeUsersGet"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_users_get_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_users_post" {
  statement_id  = "AllowAPIGatewayInvokeUsersPost"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_users_post_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_get_parameters" {
  statement_id  = "AllowAPIGatewayInvokeParametersGet"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_parameters_get_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_post_parameters" {
  statement_id  = "AllowAPIGatewayInvokeParametersPost"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_parameters_post_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_get_sensor_data" {
  statement_id  = "AllowAPIGatewayInvokeSensorDataGet"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_sensor_data_get_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_get_images" {
  statement_id  = "AllowAPIGatewayInvokeGetImages"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_get_images_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_get_reports" {
  statement_id  = "AllowAPIGatewayInvokeReportsGet"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_reports_get_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_post_reports" {
  statement_id  = "AllowAPIGatewayInvokeReportsPost"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_reports_post_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ----------------------------------------
# /callback (Cognito OAuth redirect)
# ----------------------------------------
resource "aws_api_gateway_resource" "callback" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "callback"
}

resource "aws_api_gateway_method" "callback_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.callback.id
  http_method   = "GET"
  authorization = "NONE" # OAuth callback no requiere autorización previa
}

resource "aws_api_gateway_integration" "lambda_callback" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.callback.id
  http_method             = aws_api_gateway_method.callback_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_cognito_callback_invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke_callback" {
  statement_id  = "AllowAPIGatewayInvokeCallback"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_cognito_callback_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# =============================================================================
# DEPLOYMENT (actualizado)
# =============================================================================
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.ping_integration,
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration.drone_image_integration,

    aws_api_gateway_integration.lambda_get_users,
    aws_api_gateway_integration.lambda_post_users,
    aws_api_gateway_integration.users_options_integration,

    aws_api_gateway_integration.lambda_get_parameters,
    aws_api_gateway_integration.lambda_post_parameters,
    aws_api_gateway_integration.parameters_options_integration,

    aws_api_gateway_integration.lambda_get_sensor_data,
    aws_api_gateway_integration.sensor_data_options_integration,

    aws_api_gateway_integration.lambda_get_images,
    aws_api_gateway_integration.images_options_integration,

    aws_api_gateway_integration.lambda_get_reports,
    aws_api_gateway_integration.lambda_post_reports,
    aws_api_gateway_integration.reports_options_integration,

    aws_api_gateway_integration.lambda_callback,

    # Integration responses
    aws_api_gateway_integration_response.users_options_integration_response,
    aws_api_gateway_integration_response.parameters_options_integration_response,
    aws_api_gateway_integration_response.sensor_data_options_integration_response,
    aws_api_gateway_integration_response.images_options_integration_response,
    aws_api_gateway_integration_response.reports_options_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id

  # incluir todos los recursos/métodos/integraciones en el "hash" de despliegue
  triggers = {
    redeployment = sha1(jsonencode([
      # ping
      aws_api_gateway_resource.ping.id,
      aws_api_gateway_method.ping_get.id,
      aws_api_gateway_integration.ping_integration.id,

      # messages
      aws_api_gateway_resource.messages.id,
      aws_api_gateway_method.messages_post.id,
      aws_api_gateway_integration.sqs_integration.id,

      # callback
      aws_api_gateway_resource.callback.id,
      aws_api_gateway_method.callback_get.id,
      aws_api_gateway_integration.lambda_callback.id,

      # drones
      aws_api_gateway_resource.api.id,
      aws_api_gateway_resource.drones.id,
      aws_api_gateway_resource.drone_image.id,
      aws_api_gateway_method.drone_image_post.id,
      aws_api_gateway_integration.drone_image_integration.id,

      # users
      aws_api_gateway_resource.users.id,
      aws_api_gateway_method.get_users.id,
      aws_api_gateway_method.post_users.id,
      aws_api_gateway_method.users_options.id,
      aws_api_gateway_integration.lambda_get_users.id,
      aws_api_gateway_integration.lambda_post_users.id,
      aws_api_gateway_integration.users_options_integration.id,
      aws_api_gateway_integration_response.users_options_integration_response.id,

      # parameters
      aws_api_gateway_resource.parameters.id,
      aws_api_gateway_method.get_parameters.id,
      aws_api_gateway_method.post_parameters.id,
      aws_api_gateway_method.parameters_options.id,
      aws_api_gateway_integration.lambda_get_parameters.id,
      aws_api_gateway_integration.lambda_post_parameters.id,
      aws_api_gateway_integration.parameters_options_integration.id,
      aws_api_gateway_integration_response.parameters_options_integration_response.id,

      # sensor_data
      aws_api_gateway_resource.sensor_data.id,
      aws_api_gateway_method.get_sensor_data.id,
      aws_api_gateway_method.sensor_data_options.id,
      aws_api_gateway_integration.lambda_get_sensor_data.id,
      aws_api_gateway_integration.sensor_data_options_integration.id,
      aws_api_gateway_integration_response.sensor_data_options_integration_response.id,

      # images
      aws_api_gateway_resource.images.id,
      aws_api_gateway_method.get_images.id,
      aws_api_gateway_method.images_options.id,
      aws_api_gateway_integration.lambda_get_images.id,
      aws_api_gateway_integration.images_options_integration.id,
      aws_api_gateway_integration_response.images_options_integration_response.id,

      # reports
      aws_api_gateway_resource.reports.id,
      aws_api_gateway_method.get_reports.id,
      aws_api_gateway_method.post_reports.id,
      aws_api_gateway_method.reports_options.id,
      aws_api_gateway_integration.lambda_get_reports.id,
      aws_api_gateway_integration.lambda_post_reports.id,
      aws_api_gateway_integration.reports_options_integration.id,
      aws_api_gateway_integration_response.reports_options_integration_response.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.stage_name

  tags = {
    Name = "${var.project_name}-${var.stage_name}"
  }
}

# Method settings (métricas on, logging off)
resource "aws_api_gateway_method_settings" "throttling" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = 100
    throttling_burst_limit = 200
    metrics_enabled        = true
    logging_level          = "OFF"
  }
}

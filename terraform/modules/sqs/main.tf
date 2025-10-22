# SQS Queue for Sensor Messages
resource "aws_sqs_queue" "main" {
  name                       = "${var.project_name}-messages-queue"
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  
  # Enable server-side encryption
  kms_master_key_id                 = "alias/aws/sqs"
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = "${var.project_name}-messages-queue"
    Type = "sensor_messages"
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project_name}-messages-dlq"
  message_retention_seconds  = var.dlq_message_retention_seconds
  
  # Enable server-side encryption
  kms_master_key_id                 = "alias/aws/sqs"
  kms_data_key_reuse_period_seconds = 300

  tags = {
    Name = "${var.project_name}-messages-dlq"
  }
}

# IAM role for API Gateway to interact with SQS
resource "aws_iam_role" "api_gateway_sqs_role" {
  name = "${var.project_name}-api-gateway-sqs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-api-gateway-sqs-role"
  }
}

resource "aws_iam_role_policy" "api_gateway_sqs_policy" {
  name = "${var.project_name}-api-gateway-sqs-policy"
  role = aws_iam_role.api_gateway_sqs_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ],
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

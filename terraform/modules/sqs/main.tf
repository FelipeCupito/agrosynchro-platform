# SQS Queue for Sensor Messages
resource "aws_sqs_queue" "main" {
  name                       = "${var.project_name}-messages-queue"
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

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

  tags = {
    Name = "${var.project_name}-messages-dlq"
  }
}

# Use existing LabRole for API Gateway
data "aws_iam_role" "api_gateway_sqs_role" {
  name = "LabRole"
}

# Skip custom policies - LabRole has admin permissions

# Use existing LabRole for Fargate
data "aws_iam_role" "fargate_sqs_role" {
  name = "LabRole"
}

# Skip custom policies - LabRole has admin permissions
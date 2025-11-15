# SQS Main Queue
resource "aws_sqs_queue" "main" {
  name                       = "${var.project_name}-${var.queue_name_suffix}"
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  kms_master_key_id                 = "alias/aws/sqs"
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge({
    Name = "${var.project_name}-${var.queue_name_suffix}"
    Type = var.queue_purpose
  }, var.additional_tags)
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-${var.dlq_name_suffix}"
  message_retention_seconds = var.dlq_message_retention_seconds

  kms_master_key_id                 = "alias/aws/sqs"
  kms_data_key_reuse_period_seconds = 300

  tags = merge({
    Name = "${var.project_name}-${var.dlq_name_suffix}"
    Type = "dead_letter_queue"
  }, var.additional_tags)
}

# Use existing LabRole for API Gateway
data "aws_iam_role" "api_gateway_sqs_role" {
  name = "LabRole"
}

# Use existing LabRole for Fargate
data "aws_iam_role" "fargate_sqs_role" {
  name = "LabRole"
}

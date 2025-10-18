output "queue_id" {
  description = "SQS queue ID"
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.main.arn
}

output "queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.main.url
}

output "queue_name" {
  description = "SQS queue name"
  value       = aws_sqs_queue.main.name
}

output "dlq_id" {
  description = "SQS dead letter queue ID"
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "SQS dead letter queue ARN"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "SQS dead letter queue URL"
  value       = aws_sqs_queue.dlq.url
}

output "api_gateway_role_arn" {
  description = "IAM role ARN for API Gateway to access SQS"
  value       = data.aws_iam_role.api_gateway_sqs_role.arn
}

output "fargate_role_arn" {
  description = "IAM role ARN for Fargate to access SQS"
  value       = data.aws_iam_role.fargate_sqs_role.arn
}


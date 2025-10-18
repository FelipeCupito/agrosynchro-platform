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
  value       = aws_iam_role.api_gateway_sqs_role.arn
}

output "fargate_role_arn" {
  description = "IAM role ARN for Fargate to access SQS"
  value       = aws_iam_role.fargate_sqs_role.arn
}

# Sensor Data Queue Outputs
output "sensor_queue_id" {
  description = "Sensor data SQS queue ID"
  value       = aws_sqs_queue.sensor_data.id
}

output "sensor_queue_arn" {
  description = "Sensor data SQS queue ARN"
  value       = aws_sqs_queue.sensor_data.arn
}

output "sensor_queue_url" {
  description = "Sensor data SQS queue URL"
  value       = aws_sqs_queue.sensor_data.url
}

output "sensor_queue_name" {
  description = "Sensor data SQS queue name"
  value       = aws_sqs_queue.sensor_data.name
}

# Drone Data Queue Outputs
output "drone_queue_id" {
  description = "Drone data SQS queue ID"
  value       = aws_sqs_queue.drone_data.id
}

output "drone_queue_arn" {
  description = "Drone data SQS queue ARN"
  value       = aws_sqs_queue.drone_data.arn
}

output "drone_queue_url" {
  description = "Drone data SQS queue URL"
  value       = aws_sqs_queue.drone_data.url
}

output "drone_queue_name" {
  description = "Drone data SQS queue name"
  value       = aws_sqs_queue.drone_data.name
}
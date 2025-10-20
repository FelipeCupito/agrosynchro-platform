output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_id" {
  description = "ECS service ID"
  value       = aws_ecs_service.processing_engine.id
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.processing_engine.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.processing_engine.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.processing_engine.repository_url
}

output "security_group_id" {
  description = "Fargate security group ID"
  value       = aws_security_group.fargate.id
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = data.aws_iam_role.task.arn
}

output "execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = data.aws_iam_role.task_execution.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.fargate.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = aws_lb.fargate.zone_id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.fargate.arn
}
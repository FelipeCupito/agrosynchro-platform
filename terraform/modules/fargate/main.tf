# =============================================================================
# FARGATE MODULE - PROCESSING ENGINE
# =============================================================================
# ECS Fargate cluster para processing-engine
# Procesa mensajes de SQS y imágenes de S3
# Guarda resultados en RDS PostgreSQL
# =============================================================================

# =============================================================================
# ECS CLUSTER
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

# =============================================================================
# IAM ROLES - Using existing LabRole
# =============================================================================

# Use existing LabRole for task execution
data "aws_iam_role" "task_execution" {
  name = "LabRole"
}

# Use existing LabRole for task role
data "aws_iam_role" "task" {
  name = "LabRole"
}

# Skip custom policies - LabRole has admin permissions

# =============================================================================
# SECURITY GROUP
# =============================================================================

resource "aws_security_group" "fargate" {
  name        = "${var.project_name}-fargate-sg"
  description = "Security group for Fargate tasks"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTP for health checks
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-fargate-sg"
  }
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

resource "aws_cloudwatch_log_group" "fargate" {
  name              = "/aws/ecs/${var.project_name}-processing-engine"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-fargate-logs"
  }
}

# =============================================================================
# ECR REPOSITORY
# =============================================================================

resource "aws_ecr_repository" "processing_engine" {
  name = "${var.project_name}-processing-engine"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-processing-engine-repo"
  }
}

# =============================================================================
# ECS TASK DEFINITION
# =============================================================================

resource "aws_ecs_task_definition" "processing_engine" {
  family                   = "${var.project_name}-processing-engine"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = data.aws_iam_role.task_execution.arn
  task_role_arn            = data.aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "processing-engine"
      image = "${aws_ecr_repository.processing_engine.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "SQS_QUEUE_URL"
          value = var.sqs_queue_url
        },
        {
          name  = "RAW_IMAGES_BUCKET"
          value = var.raw_images_bucket_name
        },
        {
          name  = "PROCESSED_IMAGES_BUCKET"
          value = var.processed_images_bucket_name
        },
        {
          name  = "DB_HOST"
          value = var.rds_endpoint
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = var.rds_db_name
        },
        {
          name  = "DB_USER"
          value = var.rds_username
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = var.rds_password_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.fargate.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command = ["CMD-SHELL", "curl -f http://localhost:8080/ping || exit 1"]
        interval = 30
        timeout = 5
        retries = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-processing-engine-task"
  }
}

# =============================================================================
# ECS SERVICE
# =============================================================================

resource "aws_ecs_service" "processing_engine" {
  name            = "${var.project_name}-processing-engine"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.processing_engine.arn
  launch_type     = "FARGATE"
  desired_count   = var.fargate_desired_count

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.fargate.id]
    assign_public_ip = false
  }

  # Auto scaling
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = {
    Name = "${var.project_name}-processing-engine-service"
  }
}

# =============================================================================
# AUTO SCALING
# =============================================================================

resource "aws_appautoscaling_target" "fargate" {
  max_capacity       = var.fargate_max_capacity
  min_capacity       = var.fargate_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.processing_engine.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "fargate_cpu" {
  name               = "${var.project_name}-fargate-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.fargate.resource_id
  scalable_dimension = aws_appautoscaling_target.fargate.scalable_dimension
  service_namespace  = aws_appautoscaling_target.fargate.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
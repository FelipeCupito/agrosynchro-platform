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

  # Container Insights disabled for AWS Academy compatibility
  # setting {
  #   name  = "containerInsights"
  #   value = "enabled"
  # }

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
  description = "Security group for Fargate processing tasks"
  vpc_id      = var.vpc_id

  # Allow HTTP from ALB (will be added via separate rule)
  # ingress rules added separately to avoid circular dependency

  # Only outbound access needed (SQS, S3, RDS, ECR)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access for AWS APIs"
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.db_subnet_cidrs
    description = "PostgreSQL access to database subnets"
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
  
  # Runtime platform for x86_64 compatibility
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name  = "processing-engine"
      image = "${aws_ecr_repository.processing_engine.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
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
        },
        {
          name  = "DB_PASSWORD"
          value = var.rds_password
        }
      ]

      # Secrets disabled for AWS Academy compatibility
      # secrets = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.fargate.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
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

  load_balancer {
    target_group_arn = aws_lb_target_group.fargate.arn
    container_name   = "processing-engine"
    container_port   = 8080
  }

  # Wait for ALB target group
  depends_on = [aws_lb_listener.fargate]

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

# =============================================================================
# APPLICATION LOAD BALANCER
# =============================================================================

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access from internet"
  }

  egress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTP access to Fargate tasks"
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "fargate" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "fargate" {
  name     = "${var.project_name}-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "${var.project_name}-target-group"
  }
}

# Listener
resource "aws_lb_listener" "fargate" {
  load_balancer_arn = aws_lb.fargate.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fargate.arn
  }

  tags = {
    Name = "${var.project_name}-alb-listener"
  }
}

# =============================================================================
# SECURITY GROUP RULES (separate to avoid circular dependency)
# =============================================================================

# Allow ALB to access Fargate
resource "aws_security_group_rule" "alb_to_fargate" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.fargate.id
  description              = "HTTP access from ALB to Fargate"
}
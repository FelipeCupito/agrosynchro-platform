# =============================================================================
# RDS MODULE - POSTGRESQL DATABASE
# =============================================================================
# RDS PostgreSQL con read replica para datos de sensores e imágenes
# Incluye Secrets Manager para passwords
# =============================================================================

# Get current region
data "aws_region" "current" {}

# =============================================================================
# SECRETS MANAGER - DISABLED FOR AWS ACADEMY COMPATIBILITY
# =============================================================================
# AWS Academy doesn't support Secrets Manager service
# Using direct password variable instead

# =============================================================================
# SUBNET GROUP
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# =============================================================================
# SECURITY GROUP
# =============================================================================

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.app_subnet_cidrs
    description = "PostgreSQL access from application subnets only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# =============================================================================
# PARAMETER GROUP
# =============================================================================

resource "aws_db_parameter_group" "postgresql" {
  family = "postgres15"
  name   = "${var.project_name}-postgres-params"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "${var.project_name}-postgres-params"
  }
}

# =============================================================================
# RDS INSTANCE (PRIMARY)
# =============================================================================

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = "15.8"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.postgresql.name

  backup_retention_period = var.backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Multi-AZ for high availability
  multi_az = true

  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection

  # Enable automated backups for read replica
  copy_tags_to_snapshot = true
  
  # Performance Insights and Enhanced Monitoring disabled for AWS Academy
  performance_insights_enabled = false
  monitoring_interval = 0

  # Enable logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${var.project_name}-postgres-primary"
    Type = "primary"
  }
}

# =============================================================================
# READ REPLICA
# =============================================================================

resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier                = "${var.project_name}-postgres-replica"
  replicate_source_db       = aws_db_instance.main.identifier
  instance_class            = var.replica_instance_class
  auto_minor_version_upgrade = false
  
  # Ensure primary is available before creating replica
  depends_on = [aws_db_instance.main]
  
  # Force read replica to different AZ than primary
  availability_zone = aws_db_instance.main.availability_zone == "${data.aws_region.current.name}a" ? "${data.aws_region.current.name}b" : "${data.aws_region.current.name}a"

  vpc_security_group_ids = [aws_security_group.rds.id]
  
  # Performance Insights and Enhanced Monitoring disabled for AWS Academy
  performance_insights_enabled = false
  monitoring_interval = 0

  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-postgres-replica"
    Type = "replica"
  }
}

# =============================================================================
# ENHANCED MONITORING IAM ROLE - DISABLED FOR AWS ACADEMY
# =============================================================================
# Enhanced Monitoring requires service-linked roles which may not be available in AWS Academy
# resource "aws_iam_role" "rds_monitoring" {
#   count = var.monitoring_interval > 0 ? 1 : 0
#   name  = "${var.project_name}-rds-monitoring-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "monitoring.rds.amazonaws.com"
#         }
#       }
#     ]
#   })
# }
#
# resource "aws_iam_role_policy_attachment" "rds_monitoring" {
#   count      = var.monitoring_interval > 0 ? 1 : 0
#   role       = aws_iam_role.rds_monitoring[0].name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
# }

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

# CloudWatch Log Group - RDS creates this automatically
# resource "aws_cloudwatch_log_group" "postgresql" {
#   name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/postgresql"
#   retention_in_days = 14
# 
#   lifecycle {
#     ignore_changes = [name]
#   }
# 
#   tags = {
#     Name = "${var.project_name}-postgres-logs"
#   }
# }

resource "aws_cloudwatch_log_group" "upgrade" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/upgrade"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-postgres-upgrade-logs"
  }
}
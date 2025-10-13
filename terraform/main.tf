# Creación de la VPC
resource "aws_vpc" "agrosynchro_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "AgroSynchro"
  }
}

# Creación de Subredes
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.agrosynchro_vpc.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "publica-1"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.agrosynchro_vpc.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = "us-east-1a"
  tags = {
    Name = "privada-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.agrosynchro_vpc.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "publica-2"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.agrosynchro_vpc.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "us-east-1b"
  tags = {
    Name = "privada-2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.agrosynchro_vpc.id
  tags = {
    Name = "AgroSynchro-IGW"
  }
}

# NAT Gateways y Elastic IPs
resource "aws_eip" "nat_eip_1" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.gw]
  tags = {
    Name = "nat-eip-1"
  }
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id
  depends_on    = [aws_internet_gateway.gw]
  tags = {
    Name = "nat-gateway-1"
  }
}

resource "aws_eip" "nat_eip_2" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.gw]
  tags = {
    Name = "nat-eip-2"
  }
}

resource "aws_nat_gateway" "nat_gateway_2" {
  allocation_id = aws_eip.nat_eip_2.id
  subnet_id     = aws_subnet.public_subnet_2.id
  depends_on    = [aws_internet_gateway.gw]
  tags = {
    Name = "nat-gateway-2"
  }
}

# Tablas de Ruteo
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.agrosynchro_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "route-publica"
  }
}

resource "aws_route_table" "private_route_table_1" {
  vpc_id = aws_vpc.agrosynchro_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway_1.id
  }

  tags = {
    Name = "route-privada-1"
  }
}

resource "aws_route_table" "private_route_table_2" {
  vpc_id = aws_vpc.agrosynchro_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway_2.id
  }

  tags = {
    Name = "route-privada-2"
  }
}

# Asociaciones de Tablas de Ruteo
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table_1.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table_2.id
}

# Security Groups
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]  # Solo tu IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

resource "aws_security_group" "webserver_sg" {
  name        = "webserver-sg"
  description = "Security group for webservers"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "webserver-sg"
  }
}

resource "aws_security_group" "api_sg" {
  name        = "api-sg"
  description = "Security group for API"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "api-sg"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# Processing Engine Security Group
resource "aws_security_group" "processing_engine_sg" {
  name        = "processing-engine-sg"
  description = "Security group for Processing Engine"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id, aws_security_group.webserver_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "processing-engine-sg"
  }
}

# IoT Gateway Security Group
resource "aws_security_group" "iot_gateway_sg" {
  name        = "iot-gateway-sg"
  description = "Security group for IoT Gateway"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iot-gateway-sg"
  }
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami                    = "ami-0583d8c7a9c35822c"  # Amazon Linux 2023
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = var.key_pair_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git
  EOF
  )

  tags = {
    Name = "bastion-host"
  }
}

# Instancias EC2 para Microservicios
resource "aws_instance" "web_dashboard_frontend" {
  ami                    = "ami-0583d8c7a9c35822c"  # Amazon Linux 2023
  instance_type          = var.instance_type_web
  subnet_id              = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.webserver_sg.id]
  key_name               = var.key_pair_name

  tags = {
    Name = "web-dashboard-frontend"
    Service = "frontend"
  }
}

resource "aws_instance" "web_dashboard_backend" {
  ami                    = "ami-0583d8c7a9c35822c"  # Amazon Linux 2023
  instance_type          = var.instance_type_api
  subnet_id              = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]
  key_name               = var.key_pair_name

  tags = {
    Name = "web-dashboard-backend"
    Service = "backend"
  }
}

resource "aws_instance" "processing_engine" {
  ami                    = "ami-0583d8c7a9c35822c"  # Amazon Linux 2023
  instance_type          = var.instance_type_api
  subnet_id              = aws_subnet.private_subnet_2.id
  vpc_security_group_ids = [aws_security_group.processing_engine_sg.id]
  key_name               = var.key_pair_name

  tags = {
    Name = "processing-engine"
    Service = "processing"
  }
}

resource "aws_instance" "iot_gateway" {
  ami                    = "ami-0583d8c7a9c35822c"  # Amazon Linux 2023
  instance_type          = var.instance_type_api
  subnet_id              = aws_subnet.private_subnet_2.id
  vpc_security_group_ids = [aws_security_group.iot_gateway_sg.id]
  key_name               = var.key_pair_name

  tags = {
    Name = "iot-gateway"
    Service = "iot-gateway"
  }
}

# Load Balancer
resource "aws_lb" "load_balancer_agro" {
  name               = "load-balancer-agro"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = false

  tags = {
    Name = "load-balancer-agro"
  }
}

# Target Groups con Health Checks
resource "aws_lb_target_group" "frontend_tg" {
  name     = "frontend-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.agrosynchro_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "frontend-tg"
  }
}

resource "aws_lb_target_group" "backend_tg" {
  name     = "backend-target-group"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.agrosynchro_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "backend-tg"
  }
}

resource "aws_lb_target_group" "processing_engine_tg" {
  name     = "processing-engine-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.agrosynchro_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "processing-engine-tg"
  }
}

resource "aws_lb_target_group" "iot_gateway_tg" {
  name     = "iot-gateway-tg"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = aws_vpc.agrosynchro_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "iot-gateway-tg"
  }
}

# Listeners
resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.load_balancer_agro.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.load_balancer_agro.arn
  port              = "3000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }
}

resource "aws_lb_listener" "processing_engine_listener" {
  load_balancer_arn = aws_lb.load_balancer_agro.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.processing_engine_tg.arn
  }
}

resource "aws_lb_listener" "iot_gateway_listener" {
  load_balancer_arn = aws_lb.load_balancer_agro.arn
  port              = "8081"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.iot_gateway_tg.arn
  }
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "frontend_attachment" {
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.web_dashboard_frontend.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "backend_attachment" {
  target_group_arn = aws_lb_target_group.backend_tg.arn
  target_id        = aws_instance.web_dashboard_backend.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "processing_engine_attachment" {
  target_group_arn = aws_lb_target_group.processing_engine_tg.arn
  target_id        = aws_instance.processing_engine.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "iot_gateway_attachment" {
  target_group_arn = aws_lb_target_group.iot_gateway_tg.arn
  target_id        = aws_instance.iot_gateway.id
  port             = 8081
}

# RDS Subnet Group
resource "aws_db_subnet_group" "agrosynchro_db_subnet_group" {
  name       = "agrosynchro-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "AgroSynchro DB subnet group"
  }
}

# Database Security Group
resource "aws_security_group" "database_sg" {
  name        = "database-sg"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id, aws_security_group.processing_engine_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-sg"
  }
}

# RDS PostgreSQL Database
resource "aws_db_instance" "agrosynchro_database" {
  identifier             = "agrosynchro-db"
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type          = "gp2"
  engine                = "postgres"
  engine_version        = "15.4"
  instance_class        = "db.t3.micro"
  db_name               = "agrosynchro"
  username              = var.db_username
  password              = var.db_password
  parameter_group_name  = "default.postgres15"
  
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.agrosynchro_db_subnet_group.name
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = true
  deletion_protection = false
  
  tags = {
    Name = "AgroSynchro Database"
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "agrosynchro_redis_subnet_group" {
  name       = "agrosynchro-redis-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "AgroSynchro Redis subnet group"
  }
}

# Redis Security Group
resource "aws_security_group" "redis_sg" {
  name        = "redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.processing_engine_sg.id, aws_security_group.iot_gateway_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-sg"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_replication_group" "agrosynchro_redis" {
  replication_group_id         = "agrosynchro-redis"
  description                  = "Redis cluster for AgroSynchro message queue"
  
  port                        = 6379
  parameter_group_name        = "default.redis7"
  node_type                   = "cache.t3.micro"
  num_cache_clusters          = 1
  
  subnet_group_name           = aws_elasticache_subnet_group.agrosynchro_redis_subnet_group.name
  security_group_ids          = [aws_security_group.redis_sg.id]
  
  at_rest_encryption_enabled  = false
  transit_encryption_enabled  = false
  auth_token                  = var.redis_password
  
  tags = {
    Name = "AgroSynchro Redis"
  }
}

# S3 Bucket para imágenes de drones
resource "aws_s3_bucket" "agrosynchro_drone_images" {
  bucket = "agrosynchro-drone-images-${random_string.bucket_suffix.result}"

  tags = {
    Name = "AgroSynchro Drone Images"
  }
}

# Random string para hacer único el nombre del bucket
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "agrosynchro_drone_images_versioning" {
  bucket = aws_s3_bucket.agrosynchro_drone_images.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "agrosynchro_drone_images_encryption" {
  bucket = aws_s3_bucket.agrosynchro_drone_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "agrosynchro_drone_images_pab" {
  bucket = aws_s3_bucket.agrosynchro_drone_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
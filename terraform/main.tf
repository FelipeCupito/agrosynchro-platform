# Creación de la VPC
resource "aws_vpc" "agrosynchro_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "AgroSynchro"
  }
}

# Creación de Subredes
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.agrosynchro_vpc.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = "us-east-1d"
  map_public_ip_on_launch = true
  tags = {
    Name = "publica-1"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.agrosynchro_vpc.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = "us-east-1d"
  tags = {
    Name = "privada-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.agrosynchro_vpc.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "publica-2"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.agrosynchro_vpc.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "us-east-1a"
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
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id
  tags = {
    Name = "nat-gateway-1"
  }
}

resource "aws_eip" "nat_eip_2" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway_2" {
  allocation_id = aws_eip.nat_eip_2.id
  subnet_id     = aws_subnet.public_subnet_2.id
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
resource "aws_security_group" "webserver_sg" {
  name        = "webserver-sg"
  description = "Security group for webservers"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "api_sg" {
  name        = "api-sg"
  description = "Security group for API"
  vpc_id      = aws_vpc.agrosynchro_vpc.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instancias EC2
resource "aws_instance" "webserver_privada_1" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = var.instance_type_web
  subnet_id     = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.webserver_sg.id]

  tags = {
    Name = "webserver-privada-1"
  }
}

resource "aws_instance" "api_privada_1" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = var.instance_type_api
  subnet_id     = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  tags = {
    Name = "api-privada-1"
  }
}

# Load Balancer
resource "aws_lb" "load_balancer_agro" {
  name               = "load-balancer-agro"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.webserver_sg.id, aws_security_group.api_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
}

# Target Groups
resource "aws_lb_target_group" "webserver_tg" {
  name     = "grupo-destino-webserver"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.agrosynchro_vpc.id
}

resource "aws_lb_target_group" "api_tg" {
  name     = "grupo-destino-api"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.agrosynchro_vpc.id
}

# Listeners
resource "aws_lb_listener" "webserver_listener" {
  load_balancer_arn = aws_lb.load_balancer_agro.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webserver_tg.arn
  }
}

resource "aws_lb_listener" "api_listener" {
  load_balancer_arn = aws_lb.load_balancer_agro.arn
  port              = "3000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "webserver_attachment" {
  target_group_arn = aws_lb_target_group.webserver_tg.arn
  target_id        = aws_instance.webserver_privada_1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "api_attachment" {
  target_group_arn = aws_lb_target_group.api_tg.arn
  target_id        = aws_instance.api_privada_1.id
  port             = 3000
}
variable "aws_region" {
  description = "Region de AWS"
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "Bloque CIDR para la VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "Bloque CIDR para la subred pública 1"
  default     = "10.0.2.0/24"
}

variable "private_subnet_1_cidr" {
  description = "Bloque CIDR para la subred privada 1"
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "Bloque CIDR para la subred pública 2"
  default     = "10.0.4.0/24"
}

variable "private_subnet_2_cidr" {
  description = "Bloque CIDR para la subred privada 2"
  default     = "10.0.3.0/24"
}

variable "instance_type_web" {
  description = "Tipo de instancia para el servidor web"
  default     = "t2.medium"
}

variable "instance_type_api" {
  description = "Tipo de instancia para el servidor de API"
  default     = "t2.medium"
}

variable "your_ip" {
  description = "Tu dirección IP para acceso SSH"
  default     = "0.0.0.0/0"  # Cambiar por tu IP real en producción
}

variable "key_pair_name" {
  description = "Nombre del key pair para las instancias EC2"
  default     = "my-key"  # Cambiar por tu key pair real
}

variable "docker_compose_file" {
  description = "Contenido del archivo docker-compose"
  default     = ""
}

variable "db_username" {
  description = "Username para la base de datos RDS"
  default     = "agrosynchro"
}

variable "db_password" {
  description = "Password para la base de datos RDS"
  default     = "agrosynchro123"
  sensitive   = true
}

variable "redis_password" {
  description = "Password para ElastiCache Redis"
  default     = "agroredispass123"
  sensitive   = true
}

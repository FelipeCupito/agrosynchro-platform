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

variable "db_subnet_1_cidr" {
  description = "Bloque CIDR para la subred de base de datos 1"
  default     = "10.0.5.0/24"
}

variable "db_subnet_2_cidr" {
  description = "Bloque CIDR para la subred de base de datos 2"
  default     = "10.0.6.0/24"
}

variable "your_ip" {
  description = "Tu dirección IP para acceso SSH"
  default     = "0.0.0.0/0"  # Cambiar por tu IP real en producción
}

variable "key_pair_name" {
  description = "Nombre del key pair para las instancias EC2"
  default     = "my-key"  # Cambiar por tu key pair real
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

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

# Redis variable removed - using SQS instead

variable "aws_profile" {
  description = "AWS profile to use"
  default     = "default"
}


variable "create_read_replica" {
  description = "Whether to create RDS read replica"
  type        = bool
  default     = true
}

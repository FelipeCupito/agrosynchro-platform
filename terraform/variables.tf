variable "aws_region" {
  description = "Region de AWS"
  type        = string
}

variable "vpc_cidr_block" {
  description = "Bloque CIDR para la VPC"
  type        = string
}

variable "public_subnet_1_cidr" {
  description = "Bloque CIDR para la subred pública 1"
  type        = string
}

variable "private_subnet_1_cidr" {
  description = "Bloque CIDR para la subred privada 1"
  type        = string
}

variable "public_subnet_2_cidr" {
  description = "Bloque CIDR para la subred pública 2"
  type        = string
}

variable "private_subnet_2_cidr" {
  description = "Bloque CIDR para la subred privada 2"
  type        = string
}

variable "db_subnet_1_cidr" {
  description = "Bloque CIDR para la subred de base de datos 1"
  type        = string
}

variable "db_subnet_2_cidr" {
  description = "Bloque CIDR para la subred de base de datos 2"
  type        = string
}

variable "your_ip" {
  description = "Tu dirección IP para acceso SSH"
  type        = string
}

variable "key_pair_name" {
  description = "Nombre del key pair para las instancias EC2"
  type        = string
}

variable "db_username" {
  description = "Username para la base de datos RDS"
  type        = string
}

variable "db_password" {
  description = "Password para la base de datos RDS"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "create_read_replica" {
  description = "Whether to create RDS read replica"
  type        = bool
  default     = false
}

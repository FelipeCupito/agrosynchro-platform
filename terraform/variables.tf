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

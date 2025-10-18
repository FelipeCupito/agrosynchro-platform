# Local environment configuration for LocalStack
aws_region = "us-east-1"
aws_profile = "default"

# Network configuration
vpc_cidr_block = "10.0.0.0/16"
public_subnet_1_cidr = "10.0.1.0/24"
public_subnet_2_cidr = "10.0.2.0/24"
private_subnet_1_cidr = "10.0.3.0/24"
private_subnet_2_cidr = "10.0.4.0/24"

# Development settings
your_ip = "0.0.0.0/0"  # Allow all for local development
key_pair_name = ""     # Not needed for LocalStack

# LocalStack endpoint override
aws_endpoint_url = "http://localhost:4566"
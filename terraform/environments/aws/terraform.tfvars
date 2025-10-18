# AWS production environment configuration
aws_region = "us-east-1"
aws_profile = "default"

# Network configuration
vpc_cidr_block = "10.0.0.0/16"
public_subnet_1_cidr = "10.0.1.0/24"
public_subnet_2_cidr = "10.0.2.0/24"
private_subnet_1_cidr = "10.0.3.0/24"
private_subnet_2_cidr = "10.0.4.0/24"

# Security settings - CHANGE THESE VALUES
your_ip = "YOUR_PUBLIC_IP/32"  # Replace with your actual IP
key_pair_name = "your-key-pair"  # Replace with your AWS key pair name

# AWS endpoint (default - remove for real AWS)
# aws_endpoint_url = ""
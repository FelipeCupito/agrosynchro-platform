# AgroSynchro - AWS Deployment
terraform apply -auto-approve -var-file="environments/aws/terraform.tfvars"

## Pasos para deployar la infraestructura en AWS:

### Prerequisites
- AWS CLI configurado con credenciales válidas
- Docker instalado
- Terraform instalado (>= 1.0)

### 1. **Configurar AWS CLI:**
```bash
aws configure
# Ingresar AWS Access Key ID, Secret Access Key, y región (us-east-1)
```

### 2. **Verificar credenciales AWS:**
```bash
aws sts get-caller-identity
```

### 3. **Ir a terraform:**
```bash
cd terraform
```

### 4. **Inicializar terraform:**
```bash
terraform init
```

### 5. **Revisar plan de despliegue:**
```bash
terraform plan -var-file="environments/aws/terraform.tfvars"
```

### 6. **Aplicar infraestructura:**
```bash
terraform apply -var-file="environments/aws/terraform.tfvars"
```

### 7. **Deployar imagen Docker a ECR:**
```bash
cd ../services/processing-engine
./build-and-deploy.sh
cd ../../terraform
```

### 8. **Aplicar cambios de Fargate (después del deploy de imagen):**
```bash
terraform apply -var-file="environments/aws/terraform.tfvars"
```

### 9. **Obtener endpoints:**
```bash
terraform output api_gateway_invoke_url
```

### 10. **Probar endpoints:**
```bash
# Reemplazar [API_URL] con la salida del comando anterior
API_URL=$(terraform output -raw api_gateway_invoke_url)

# Ping
curl -X GET "$API_URL/ping"

# Messages
curl -X POST "$API_URL/messages" \
  -H "Content-Type: application/json" \
  -d '{"message": "test from sensor"}'

# Drone image upload
curl -X POST "$API_URL/api/drones/image" \
  -H "Content-Type: multipart/form-data" \
  -F "image=@test-image.jpg" \
  -F "drone_id=drone001" \
  -F "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

## Arquitectura Desplegada

La infraestructura incluye:

- **VPC con 3 capas de subnets:**
  - Public subnets (NAT Gateway, Load Balancer)
  - Private subnets (Fargate containers)
  - Database subnets (RDS isolated)

- **Servicios principales:**
  - API Gateway (entrada principal)
  - Lambda (procesamiento de imágenes)
  - SQS + DLQ (cola de mensajes)
  - Fargate (contenedores serverless)
  - RDS PostgreSQL Multi-AZ + Read Replica
  - S3 buckets (raw + processed images)
  - ECR (registro de imágenes Docker)

- **Seguridad:**
  - Security Groups con principio de menor privilegio
  - Encryption en reposo (S3, SQS, RDS)
  - VPC endpoints para servicios AWS
  - IAM roles con LabRole (AWS Academy)

## Monitoreo

```bash
# Ver logs de CloudWatch
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/agrosynchro"
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway/agrosynchro"

# Ver métricas de API Gateway
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Cleanup

### ⚡ Automated Cleanup (Recommended)
```bash
# Limpieza completa automatizada
./cleanup.sh

# O forzar sin confirmación
./cleanup.sh --force
```

### 🔧 Manual Cleanup
```bash
# Destruir infraestructura
terraform destroy -var-file="environments/aws/terraform.tfvars"

# Eliminar imágenes ECR (opcional)
aws ecr delete-repository --repository-name agrosynchro-processing-engine --force
```

## Scripts Disponibles

### 🚀 Deployment Scripts
- `deploy.sh` - **Script principal de despliegue completo** (Terraform + ECR + validación)
- `services/processing-engine/build-and-deploy.sh` - Build y deploy a ECR solamente
- `test-e2e.sh` - **Suite de pruebas end-to-end completa**
- `cleanup.sh` - **Limpieza completa de recursos AWS** (destruye toda la infraestructura)

### ⚡ Quick Start (Automated)
```bash
# Despliegue completo automatizado
./deploy.sh

# Validación post-despliegue
./test-e2e.sh

# Limpieza completa (CUIDADO: destruye todo!)
./cleanup.sh
```

### 📁 Configuration Files
- `terraform/environments/aws/terraform.tfvars` - Variables de configuración AWS

## Troubleshooting

### Error de credenciales AWS
```bash
aws configure list
aws sts get-caller-identity
```

### Error de Terraform state
```bash
terraform refresh -var-file="environments/aws/terraform.tfvars"
```

### Verificar recursos desplegados
```bash
terraform state list
terraform show
```
# AgroSynchro - Plataforma Cloud para Agricultura de Precisión

> **Arquitectura Serverless AWS** - Integración de datos IoT y análisis de imágenes de drones para optimización agrícola

## 🏗️ Arquitectura General

### Diseño Serverless (AWS)
```
📱 Ingesta Externa                    🎯 Dashboard Interno
     ↓                                        ↓
[IoT/Drones] → [API Gateway] → [SQS] → [Fargate] ← [ALB] ← [Frontend S3]
                     ↓             ↓        ↓
                [Lambda] → [S3] → [IA] → [RDS PostgreSQL]
```

### Separación de Responsabilidades
- **API Gateway**: Recepción de datos externos (sensores IoT, drones)  
- **Application Load Balancer**: Backend del dashboard web y APIs internas
- **Fargate**: Motor de procesamiento containerizado con auto-scaling
- **RDS**: Base de datos PostgreSQL Multi-AZ para persistencia

## 🚀 Despliegue Automatizado (Un Solo Comando)

```bash
# Despliegue completo automatizado
./deploy.sh
```

Este script ejecuta:
1. ✅ Validación de prerequisitos (AWS CLI, Docker, Terraform)
2. ✅ Inicialización y planificación de Terraform  
3. ✅ Despliegue de infraestructura AWS
4. ✅ Build y push de imagen Docker a ECR
5. ✅ Actualización de servicios Fargate
6. ✅ Migración automática de base de datos
7. ✅ Validación de endpoints

## 📋 Pasos manuales (para debugging):

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
# Obtener URLs de los endpoints
API_URL=$(terraform output -raw api_gateway_invoke_url)
ALB_URL=$(terraform output -raw alb_health_check_url)

# === API Gateway (Ingesta Externa) ===
# Health check
curl -X GET "$API_URL/ping"

# Sensor data
curl -X POST "$API_URL/messages" \
  -H "Content-Type: application/json" \
  -d '{"message": "test from sensor"}'

# Drone image upload  
curl -X POST "$API_URL/api/drones/image" \
  -H "Content-Type: multipart/form-data" \
  -F "image=@test-image.jpg" \
  -F "drone_id=drone001" \
  -F "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# === ALB Dashboard (APIs Internas) ===
# Database health check
curl -X GET "$ALB_URL"

# Sensor averages
curl -X GET "${ALB_URL%/health}/api/sensors/average"

# Image analysis results
curl -X GET "${ALB_URL%/health}/api/images/analysis?limit=5"
```

## 🏗️ Arquitectura Desplegada

### Infraestructura de Red (VPC)
```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                   │
├─────────────────────────────────────────────────────────────┤
│ 🌐 Public Subnets (10.0.1-2.0/24)                          │
│   ├── Internet Gateway                                      │
│   ├── NAT Gateways                                         │
│   └── Application Load Balancer                            │
├─────────────────────────────────────────────────────────────┤  
│ 🔒 Private Subnets (10.0.3-4.0/24)                         │
│   ├── ECS Fargate Containers                               │
│   └── Processing Engine Services                           │
├─────────────────────────────────────────────────────────────┤
│ 🗄️ Database Subnets (10.0.5-6.0/24)                        │
│   └── RDS PostgreSQL (Multi-AZ)                            │
└─────────────────────────────────────────────────────────────┘
```

### Servicios AWS Desplegados

#### 🔄 Ingesta y Procesamiento
- **API Gateway**: Punto de entrada para datos externos
- **AWS Lambda**: Procesamiento de uploads de imágenes  
- **SQS + DLQ**: Cola de mensajes con manejo de errores
- **ECS Fargate**: Contenedores auto-escalables (1-10 instancias)

#### 💾 Almacenamiento y Datos
- **RDS PostgreSQL**: Base de datos Multi-AZ con backups automáticos
- **S3 Buckets**: Almacenamiento de imágenes (raw + procesadas)
- **ECR**: Registro privado de imágenes Docker
- **Secrets Manager**: Gestión segura de passwords

#### 🌐 Acceso y Frontend  
- **Application Load Balancer**: Backend APIs para dashboard
- **API Gateway**: APIs públicas para ingesta de datos

### 🔐 Seguridad Implementada
- **Red**: Security Groups con principio de menor privilegio
- **Datos**: Cifrado AES-256 en reposo (S3, SQS, RDS)
- **Tráfico**: HTTPS/TLS para todas las comunicaciones
- **Acceso**: IAM roles con permisos mínimos (LabRole para AWS Academy)
- **Aislamiento**: VPC privada con subnets aisladas por función

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
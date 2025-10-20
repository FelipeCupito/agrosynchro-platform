# AgroSynchro - Arquitectura Detallada

## 🎯 Visión General

AgroSynchro es una plataforma cloud para agricultura de precisión que integra datos de sensores IoT e imágenes de drones para generar recomendaciones agronómicas basadas en evidencia. La arquitectura está diseñada como un sistema serverless en AWS que separa claramente la ingesta de datos externa del backend interno del dashboard.

## 🏗️ Arquitectura de Alto Nivel

### Principios de Diseño

1. **Separación de Responsabilidades**
   - API Gateway para ingesta externa de datos
   - Application Load Balancer para backend del dashboard interno

2. **Escalabilidad Automática**
   - ECS Fargate con auto-scaling basado en CPU
   - SQS para manejo asíncrono de cargas variables

3. **Seguridad por Capas**
   - VPC con subnets aisladas por función
   - Cifrado en tránsito y en reposo
   - IAM roles con permisos mínimos

4. **Disponibilidad y Resiliencia**
   - RDS Multi-AZ para alta disponibilidad
   - Dead Letter Queue para manejo de errores
   - Health checks automáticos en todos los niveles

## 🔄 Flujos de Datos

### 1. Ingesta de Datos de Sensores IoT

```
[Sensor IoT] 
    ↓ POST /messages
[API Gateway] 
    ↓ JSON payload
[SQS Queue]
    ↓ Message polling
[Fargate Container]
    ↓ Parse & validate
[RDS PostgreSQL]
```

**Detalles técnicos:**
- Sensores envían datos cada 5 minutos
- API Gateway aplica throttling (100 req/sec, burst 200)
- SQS garantiza entrega de mensajes
- Fargate procesa en lotes para eficiencia

### 2. Procesamiento de Imágenes de Drones

```
[Drone] 
    ↓ POST /api/drones/image (multipart)
[API Gateway]
    ↓ Trigger
[Lambda Function]
    ↓ Upload
[S3 Raw Images]
    ↓ Metadata → SQS
[Fargate Container]
    ↓ Download & analyze
[IA Simulation] → [S3 Processed] + [RDS Analysis Results]
```

**Detalles técnicos:**
- Lambda maneja el upload inicial para optimizar costos
- S3 con versionado para preservar historial
- IA simulada analiza condición del campo
- Resultados almacenados para consultas posteriores

### 3. Consultas del Dashboard

```
[Frontend Web]
    ↓ HTTP requests
[Application Load Balancer]
    ↓ Forward to healthy targets
[Fargate Container]
    ↓ Query database
[RDS PostgreSQL] → [Response] → [Frontend]
```

**Detalles técnicos:**
- ALB distribuye carga entre contenedores disponibles
- Health checks cada 30 segundos en `/health`
- Conexión directa a RDS desde VPC privada
- Respuestas en JSON para consumo del frontend

## 🗄️ Modelo de Datos

### Base de Datos: PostgreSQL 15.8

#### Tabla: `users`
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT NOT NULL
);
```

#### Tabla: `sensor_data`  
```sql
CREATE TABLE sensor_data (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    timestamp TIMESTAMP NOT NULL,
    measure TEXT NOT NULL,        -- 'temperature', 'humidity', 'soil_moisture'
    value REAL NOT NULL
);
```

#### Tabla: `drone_images`
```sql
CREATE TABLE drone_images (
    id SERIAL PRIMARY KEY,
    drone_id VARCHAR(255),
    raw_s3_key VARCHAR(500),           -- S3 path to original image
    processed_s3_key VARCHAR(500),     -- S3 path to processed image  
    field_status VARCHAR(50) DEFAULT 'unknown',  -- 'excellent', 'good', 'fair', 'poor', 'critical'
    analysis_confidence REAL DEFAULT 0.0,        -- 0.0 to 1.0
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    analyzed_at TIMESTAMP
);
```

#### Tabla: `parameters`
```sql
CREATE TABLE parameters (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    temperature REAL,
    humidity REAL,
    soil_moisture REAL,
    -- Thresholds for alerts
    min_temperature REAL,
    max_temperature REAL,
    min_humidity REAL,
    max_humidity REAL,
    min_soil_moisture REAL,
    max_soil_moisture REAL
);
```

## 🌐 Infraestructura de Red

### VPC Design (10.0.0.0/16)

```
┌─────────────────────────────────────────────────────────────┐
│                     Internet Gateway                        │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────────────────┐
│              PUBLIC SUBNETS (Multi-AZ)                     │
│  ┌─────────────────────┐  ┌─────────────────────────────┐    │
│  │ us-east-1a          │  │ us-east-1b                  │    │  
│  │ 10.0.1.0/24         │  │ 10.0.2.0/24                 │    │
│  │ • NAT Gateway       │  │ • NAT Gateway               │    │
│  │ • ALB Public        │  │ • ALB Public                │    │
│  └─────────────────────┘  └─────────────────────────────┘    │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────────────────┐
│             PRIVATE SUBNETS (Application)                  │
│  ┌─────────────────────┐  ┌─────────────────────────────┐    │
│  │ us-east-1a          │  │ us-east-1b                  │    │
│  │ 10.0.3.0/24         │  │ 10.0.4.0/24                 │    │
│  │ • Fargate Tasks     │  │ • Fargate Tasks             │    │
│  │ • Processing Engine │  │ • Processing Engine         │    │
│  └─────────────────────┘  └─────────────────────────────┘    │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────────────────┐
│             DATABASE SUBNETS (Isolated)                    │
│  ┌─────────────────────┐  ┌─────────────────────────────┐    │
│  │ us-east-1a          │  │ us-east-1b                  │    │
│  │ 10.0.5.0/24         │  │ 10.0.6.0/24                 │    │
│  │ • RDS Primary       │  │ • RDS Standby               │    │
│  │ • Multi-AZ          │  │ • Multi-AZ                  │    │
│  └─────────────────────┘  └─────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Security Groups

#### ALB Security Group
```
Ingress:
- Port 80 from 0.0.0.0/0 (HTTP from internet)

Egress:  
- Port 8080 to Fargate SG (HTTP to containers)
```

#### Fargate Security Group
```
Ingress:
- Port 8080 from ALB SG (HTTP from load balancer)

Egress:
- Port 443 to 0.0.0.0/0 (HTTPS to AWS APIs)
- Port 5432 to RDS SG (PostgreSQL to database)
```

#### RDS Security Group  
```
Ingress:
- Port 5432 from Fargate SG (PostgreSQL from containers)

Egress:
- None (database doesn't initiate outbound connections)
```

## 🚀 Servicios de Aplicación

### ECS Fargate - Processing Engine

**Configuración del Contenedor:**
```yaml
CPU: 512 units (0.5 vCPU)
Memory: 1024 MB (1 GB)
Platform: Linux x86_64
Port: 8080
Health Check: GET /health every 30s
```

**Variables de Entorno:**
```bash
AWS_DEFAULT_REGION=us-east-1
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/.../agrosynchro-processing-queue
RAW_IMAGES_BUCKET=agrosynchro-raw-images
PROCESSED_IMAGES_BUCKET=agrosynchro-processed-images
DB_HOST=agrosynchro-postgres.xxxxx.us-east-1.rds.amazonaws.com
DB_PORT=5432
DB_NAME=agrosynchro
DB_USER=agro
DB_PASSWORD=[from Secrets Manager]
```

**Auto Scaling:**
```yaml
Min Capacity: 1 task
Max Capacity: 10 tasks
Target CPU: 70%
Scale Out: +1 task if CPU > 70% for 2 minutes
Scale In: -1 task if CPU < 50% for 5 minutes
```

### RDS PostgreSQL

**Configuración:**
```yaml
Engine: PostgreSQL 15.8
Instance Class: db.t3.micro (AWS Academy)
Storage: 20GB GP3 SSD, encrypted
Multi-AZ: Enabled (automatic failover)
Backup: 7 days retention
Maintenance: Sunday 04:00-05:00 UTC
Parameter Group: Custom (logging enabled)
```

**Conexión:**
```yaml
Endpoint: agrosynchro-postgres.xxxxx.us-east-1.rds.amazonaws.com
Port: 5432
Database: agrosynchro
Username: agro
Password: Stored in AWS Secrets Manager
SSL: Required
```

### SQS + Dead Letter Queue

**Main Queue: `agrosynchro-processing-queue`**
```yaml
Message Retention: 14 days
Visibility Timeout: 300 seconds (5 minutes)
Max Receive Count: 3 attempts
Dead Letter Queue: agrosynchro-dlq
Encryption: AES-256-GCM
FIFO: No (standard queue for higher throughput)
```

**Dead Letter Queue: `agrosynchro-dlq`**
```yaml
Message Retention: 14 days
Purpose: Failed messages after 3 attempts
Monitoring: CloudWatch alarms on message count
```

### S3 Buckets

**Raw Images: `agrosynchro-raw-images`**
```yaml
Versioning: Enabled
Encryption: AES-256
Lifecycle: Delete versions > 30 days
Access: Private (Fargate and Lambda only)
```

**Processed Images: `agrosynchro-processed-images`**  
```yaml
Versioning: Enabled
Encryption: AES-256
Lifecycle: Delete versions > 90 days
Access: Private (Fargate only)
```

## 📊 Monitoreo y Observabilidad

### CloudWatch Metrics

**API Gateway:**
- Request count and latency
- 4XX/5XX error rates
- Throttling events

**ECS Fargate:**
- CPU and memory utilization
- Task count and health
- Container restart events

**RDS:**
- Connection count
- Query performance
- Storage utilization

**SQS:**
- Messages sent/received
- Queue depth
- Dead letter queue messages

### CloudWatch Logs

```
/aws/apigateway/agrosynchro     - API Gateway access logs
/aws/ecs/agrosynchro-processing - Fargate container logs  
/aws/lambda/agrosynchro-upload  - Lambda execution logs
/aws/rds/instance/.../postgresql - Database logs
```

### Health Checks

**ALB Target Health:**
- Path: `GET /health`
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 2 consecutive failures

**Application Health Check Response:**
```json
{
  "status": "healthy",
  "timestamp": "2023-12-01T14:30:22Z",
  "uptime_seconds": 3600,
  "database_connected": true,
  "database_migrations": "completed",
  "sqs_accessible": true,
  "s3_accessible": true
}
```

## 🔐 Seguridad y Compliance

### Encryption

**In Transit:**
- HTTPS/TLS 1.2+ for all API communications
- VPC internal traffic over private subnets

**At Rest:**
- RDS: AES-256 encryption with AWS managed keys
- S3: AES-256 server-side encryption
- SQS: AES-256-GCM encryption

### Access Control

**IAM Strategy:**
- AWS Academy: Using LabRole with broad permissions
- Production: Would use least-privilege custom roles

**Network Security:**
- VPC with no direct internet access to private resources
- Security groups with minimal required ports
- Database in isolated subnet group

**Secrets Management:**
- Database passwords in AWS Secrets Manager
- No hardcoded credentials in code or containers
- Automatic password rotation (configurable)

## 🚀 Deployment Strategy

### Infrastructure as Code (Terraform)

**Modules:**
```
terraform/
├── main.tf                    # Root configuration
├── modules/
│   ├── networking/           # VPC, subnets, gateways
│   ├── api-gateway/          # API Gateway and Lambda
│   ├── sqs/                 # SQS queues and policies
│   ├── s3/                  # S3 buckets and policies
│   ├── rds/                 # PostgreSQL database
│   ├── fargate/             # ECS cluster and services
│   └── lambda/              # Image upload function
└── environments/
    └── aws/
        └── terraform.tfvars  # Environment variables
```

### Automated Deployment

**deploy.sh workflow:**
1. Prerequisites validation (AWS CLI, Docker, Terraform)
2. Terraform init and plan
3. Infrastructure deployment
4. Docker image build and ECR push
5. ECS service update with new image
6. Database migrations (automatic on container startup)
7. Endpoint validation and testing

### Database Migrations

**Automatic Migration Strategy:**
- Migrations run on container startup
- Idempotent SQL scripts (CREATE IF NOT EXISTS)
- No manual intervention required
- Logged to CloudWatch for auditing

## 📈 Escalabilidad y Performance

### Capacity Planning

**Current Configuration (AWS Academy):**
- Fargate: 1-10 tasks (0.5 CPU, 1GB RAM each)
- RDS: db.t3.micro (1 vCPU, 1GB RAM)
- SQS: Standard queue (unlimited throughput)

**Production Scaling:**
- Fargate: 2-50 tasks with larger CPU/memory
- RDS: db.t3.medium+ with read replicas
- API Gateway: Regional deployment with caching
- CloudFront: CDN for static assets

### Performance Optimizations

**Current:**
- SQS batch processing for efficiency
- Database connection pooling
- S3 multipart uploads for large images
- ECS auto-scaling based on CPU metrics

**Future Enhancements:**
- Redis caching layer for frequent queries
- Database query optimization and indexing
- Image processing optimization (thumbnails, compression)
- API response caching with ElastiCache

## 🔧 Troubleshooting Guide

### Common Issues

**Database Connection Failures:**
```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier agrosynchro-postgres

# Check security group rules
aws ec2 describe-security-groups --filters "Name=group-name,Values=agrosynchro-rds-sg"

# Test from Fargate container
curl http://alb-dns-name/health
```

**SQS Message Processing Delays:**
```bash
# Check queue depth
aws sqs get-queue-attributes --queue-url $SQS_QUEUE_URL --attribute-names All

# Check dead letter queue
aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names All

# Scale up Fargate manually if needed
aws ecs update-service --cluster agrosynchro-cluster --service agrosynchro-processing-engine --desired-count 3
```

**ALB Health Check Failures:**
```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN

# Check Fargate task health
aws ecs describe-services --cluster agrosynchro-cluster --services agrosynchro-processing-engine

# View container logs
aws logs tail /aws/ecs/agrosynchro-processing-engine --follow
```

Esta arquitectura proporciona una base sólida y escalable para AgroSynchro, separando claramente las responsabilidades y permitiendo el crecimiento futuro de la plataforma.
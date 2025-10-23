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

### 4. **Agregar Gemini API Key en el archivo report_field.py:**

### 5. **Ejecutar Script de incializacion:**
```bash
./deploy_app.sh
```

### 6. **Ejecutar Simulador:**
Una vez levantada la aplicacion, iniciar sesion, y en la nav bar se vera el numero de id del usuario
```bash
./send_sensor_data.sh
```
Esto le pedira el user id para empezar a simular la informacion de los sensores


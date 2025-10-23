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
En caso de que falle, volver a correrlo. 
### 6. **Ejecutar Simulador:**
Una vez levantada la aplicacion, iniciar sesion, y en la nav bar se vera el numero de id del usuario
```bash
./send_sensor_data.sh
```
Esto le pedira el user id para empezar a simular la informacion de los sensores

## Elección de arquitectura

Agrosynchro Cloud Architecture

Red (VPC, subnets y NAT Gateways)

La infraestructura de red se compone de subnets publicas, privadas y para la base de datos para poder aislar los diferentes niveles de la aplicacion y restringir el acceso al backend. Multiples AZs garantizan continuidad ante fallas en una zona

⸻

Almacenamiento S3

Se definieron 3 buckets:
	•	Frontend: Aloja los archivos estáticos del sitio web (HTML, CSS, JS).
	•	Imágenes sin procesar: Recibe las imágenes enviadas por drones o sensores.
	•	Imágenes procesadas: Almacena los resultados generados tras el análisis.

Justificación:
S3 ofrece almacenamiento de alta durabilidad, disponibilidad y bajo costo.
El acceso desde los servicios internos se realiza a través de un VPC Endpoint, evitando tráfico por Internet.

⸻

API Gateway

El API Gateway actúa como punto de entrada único para los clientes y servicios externos.
Expone endpoints REST que permiten:
	•	La recepción de datos desde los sensores IoT.
	•	El envío de mensajes a SQS.
	•	La invocación de funciones Lambda para procesamiento o validaciones.
	•	La integración con Cognito para autenticación.

Justificación:
API Gateway desacopla completamente la capa de acceso del backend, permite control de tráfico, autenticación, logging, rate limiting y escalabilidad automática.

⸻

SQS

SQS funciona como una cola de mensajeria intermedia entre la ingesta de datos (API Gateway y Lambda) y el procesamiento posterior (Fargate).

Justificación:
Introduce un mecanismo de comunicación asíncrono que desacopla los componentes, mejora la tolerancia a fallos y permite procesar cargas variables sin pérdida de mensajes.
Tambien facilita la escalabilidad horizontal de los servicios de procesamiento.

⸻

Fargate

El servicio Fargate ejecuta contenedores que:
	1.	Consumen mensajes de SQS.
	2.	Descargan imágenes sin procesar desde S3.
	3.	Ejecutan algoritmos de procesamiento o análisis.
	4.	Guardan los resultados en el bucket de imágenes procesadas.
	5.	Registran metadatos y resultados en RDS.

Justificación:
Fargate permite ejecutar contenedores sin administrar servidores, ajustando automáticamente la capacidad a la carga de trabajo.
El acceso a S3 se realiza mediante el VPC Endpoint, lo que elimina la necesidad de exponer el tráfico a Internet y reduce costos.

⸻

Lambda

Lambda se utiliza para operaciones rápidas y eventos desencadenados por API Gateway o SQS, tales como:
	•	Validación o transformación de datos.
	•	Envío de mensajes a la cola SQS.
	•	Comunicación con Cognito o servicios externos.

Justificación:
Permite ejecutar código bajo demanda con costos proporcionales al uso y sin administración de infraestructura.
Las funciones se despliegan dentro de la VPC, con acceso directo y seguro a RDS y otros servicios internos.

⸻

RDS

La base de datos relacional RDS almacena información estructurada y metadatos asociados a los procesos.
	•	Instancia principal: maneja las operaciones de lectura y escritura.
	•	Réplica de solo lectura: proporciona redundancia y capacidad adicional para consultas no críticas.

Justificación:
RDS asegura persistencia, integridad y disponibilidad de datos.
El aislamiento dentro de subnets privadas y las reglas de seguridad limitan el acceso únicamente a los servicios internos (Lambda y Fargate).

⸻

Cognito

Cognito gestiona la autenticación y autorización de los usuarios.
Incluye dominios personalizados, redirecciones seguras (callback y logout) y soporte para OAuth2 y OpenID Connect.

Justificación:
Proporciona autenticación centralizada y escalable sin necesidad de desarrollar ni mantener un sistema propio de gestión de usuarios.
Se integra nativamente con API Gateway y Lambda.

⸻

VPC Endpoint

El VPC Endpoint permite que los servicios dentro de la VPC (como Fargate y Lambda) accedan a S3 sin pasar por Internet.

Justificación:
Mejora la seguridad y el rendimiento, reduce la latencia y elimina costos asociados al tráfico a través de NAT Gateways.

⸻

Monitoreo y observabilidad

Los registros y métricas de API Gateway, Lambda y Fargate se centralizan en Amazon CloudWatch.
Esto incluye métricas de utilización de CPU, memoria, tráfico de red y errores de aplicación.

Justificación:
Centralizar el monitoreo permite trazabilidad, auditoría y detección temprana de fallos.
Facilita la generación de alarmas automáticas y dashboards operativos.

Flujo de datos
	1.	Los sensores IoT o drones envían datos e imágenes al API Gateway.
	2.	API Gateway invoca una Lambda que valida los datos y los envía a la cola SQS.
	3.	Fargate consume los mensajes de la cola, descarga las imágenes de S3 y ejecuta el procesamiento.
	4.	Los resultados se guardan en el bucket S3 (imágenes procesadas) y los metadatos se almacenan en RDS.
	5.	El frontend, alojado en el bucket S3 público, obtiene información a través del API Gateway.
	6.	El tráfico interno entre los servicios se mantiene dentro de la VPC y se enruta mediante el VPC Endpoint.



<img width="757" height="735" alt="image" src="https://github.com/user-attachments/assets/dd3e19b7-1bc6-4406-b067-b623e8a751b3" />

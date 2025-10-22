# AgroSynchro - API Documentation & Service Specifications

## Architecture Overview (AWS Serverless)

### Current Implementation (Serverless AWS)
```
📡 DATA INGESTION:
[IoT Sensors] → [API Gateway /messages] → [SQS Queue] → [Fargate Processing] → [RDS PostgreSQL]
[Drone Images] → [API Gateway /api/drones/image] → [Lambda Upload] → [S3 Storage] → [Fargate AI Analysis] → [RDS PostgreSQL]

📱 USER QUERIES:
[Frontend (S3)] → [API Gateway /users, /parameters, /sensor_data, /reports] → [Lambda Functions] → [RDS PostgreSQL]
```

### Service Separation
```
📡 Data Ingestion (Sensors/Drones → Database):
   API Gateway → SQS/Lambda → Fargate/S3 → RDS

📱 User Queries (Frontend → Database):  
   API Gateway → Lambda Functions → RDS
```

## AWS Services & Endpoints

### Data Ingestion Endpoints (API Gateway)
| Endpoint | Method | Purpose | Authentication |
|----------|--------|---------|---------------|
| `/ping` | GET | Health check | None |
| `/messages` | POST | IoT sensor data ingestion | None (will add Cognito) |
| `/api/drones/image` | POST | Drone image upload | None (will add Cognito) |

### User Query Endpoints (API Gateway → Lambda)
| Endpoint | Method | Purpose | Authentication |
|----------|--------|---------|---------------|
| `/users` | GET, POST | User management | Cognito |
| `/parameters` | GET, POST | User parameter configuration | Cognito |
| `/sensor_data` | GET | Retrieve sensor data | Cognito |
| `/reports` | GET, POST | Generate and retrieve reports | Cognito |
| `/callback` | GET | Cognito OAuth callback | None |

### AWS Infrastructure Services
| Service | Purpose | Configuration |
|---------|---------|---------------|
| **API Gateway** | Unified API endpoint for data ingestion and user queries | Regional, throttling enabled, Cognito auth |
| **Lambda Functions** | User query processing (users, parameters, sensor_data, reports) | VPC-enabled, RDS access |
| **ECS Fargate** | Sensor/image processing engine | Auto-scaling 1-10 instances |
| **RDS PostgreSQL** | Data persistence | Multi-AZ, encrypted |
| **SQS + DLQ** | Message queuing for sensor data | Encryption, dead letter handling |
| **S3 Buckets** | Image storage and frontend hosting | Versioning, lifecycle policies |
| **Cognito** | User authentication and authorization | OAuth2, PKCE flow |

## Message Queue Schemas (AWS SQS)

### SQS Queue Configuration
- **Main Queue**: `agrosynchro-processing-queue` - Sensor data and image metadata
- **Dead Letter Queue**: `agrosynchro-dlq` - Failed message handling
- **Encryption**: AES-256 server-side encryption
- **Retention**: 14 days for main queue, 14 days for DLQ

### Message Schemas

#### Sensor Data Message
```json
{
  "user_id": "1",
  "timestamp": "2023-12-01T14:30:22Z",
  "measurements": {
    "temperature": 24.5,
    "humidity": 65.2,
    "soil_moisture": 45.3
  }
}
```

#### Drone Data Message
```json
{
  "drone_id": "DRONE_001",
  "timestamp": "2023-12-01T14:30:22Z",
  "s3_path": "drone-images/2023/12/01/drone_001_143022.jpg"
}
```

#### Alert Message
```json
{
  "timestamp": "2023-12-01T14:30:22Z",
  "type": "anomaly",
  "message": "Temperature exceeds optimal range",
  "severity": "high"
}
```

## API Gateway Endpoints

### Base URL:
- **API Gateway**: `https://{api-gateway-url}/{stage}/` - Unified endpoint for all operations

### User Query Lambda Endpoints

### Health Endpoint

#### GET `/health`
**Purpose**: Database connectivity and system health check
**Access**: Available via ALB public endpoint
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

### Data Endpoints

#### GET `/api/sensors/average`
Get 1-minute average from 5 sensors
```json
{
  "success": true,
  "data": {
    "timestamp": "2023-12-01T14:30:22Z",
    "sensors_count": 5,
    "averages": {
      "temperature": 24.5,
      "humidity": 65.2,
      "soil_moisture": 45.3
    }
  }
}
```

#### GET `/api/images/analysis?limit=10`
Get recent image analysis results
```json
{
  "success": true,
  "data": [
    {
      "drone_id": "DRONE_001",
      "s3_path": "drone-images/2023/12/01/drone_001_143022.jpg",
      "analyzed_at": "2023-12-01T14:30:25Z",
      "field_status": "excellent"
    }
  ],
  "count": 5
}
```

**Field Status Options:**
- `excellent` - Field in perfect condition
- `good` - Field in good condition  
- `fair` - Field needs attention
- `poor` - Field has issues
- `critical` - Field requires immediate action

### Alert Configuration

#### POST `/api/alerts/configure`
Configure sensor value alerts
```json
{
  "alert_name": "temperature_alert",
  "sensor_type": "temperature",
  "min_value": 18.0,
  "max_value": 28.0,
  "enabled": true
}
```

Response:
```json
{
  "success": true,
  "alert_id": "alert_123",
  "message": "Alert configured successfully"
}
```

#### GET `/api/alerts`
Get configured alerts
```json
{
  "success": true,
  "data": [
    {
      "alert_id": "alert_123",
      "alert_name": "temperature_alert",
      "sensor_type": "temperature",
      "min_value": 18.0,
      "max_value": 28.0,
      "enabled": true,
      "created_at": "2023-12-01T14:30:22Z"
    }
  ]
}
```

## Web Service with Frontend (Port 3000) - TO IMPLEMENT

### Responsibilities
- Serve static frontend files
- Provide web interface for monitoring
- Consume data from Processing Engine API

### Frontend Views to Implement

#### 1. Dashboard View (`/`)
Main monitoring dashboard
- **Current Sensor Averages**: Cards showing temperature, humidity, soil moisture
- **Field Status**: Latest drone image analysis with status badge
- **Active Alerts**: List of triggered alerts with severity colors
- **Quick Stats**: Sensors count, recent images count

#### 2. Sensor History View (`/sensors`)
Historical sensor data visualization
- **Line Charts**: Temperature, humidity, soil moisture over time
- **Time Range Selector**: Last hour, 6h, 24h, 7 days
- **Current Values**: Real-time current averages
- **Export Data**: Button to download CSV

#### 3. Image Gallery View (`/images`)
Drone image analysis results
- **Image Grid**: Recent drone images with field status overlay
- **Status Filter**: Filter by field status (excellent, good, fair, poor, critical)
- **Image Details**: Click to see larger image with analysis details
- **Upload New Image**: Simple upload form for testing

#### 4. Alert Configuration View (`/alerts`)
Manage sensor alerts
- **Alert List**: Current configured alerts with enable/disable toggle
- **Add New Alert**: Form to create new alerts (sensor type, min/max values)
- **Alert History**: Recent triggered alerts log
- **Test Alerts**: Button to trigger test alerts

### API Endpoints (Internal)
The web service should call Processing Engine API:
- `GET http://processing-engine:8080/api/sensors/average`
- `GET http://processing-engine:8080/api/images/analysis`
- `POST http://processing-engine:8080/api/alerts/configure`
- `GET http://processing-engine:8080/api/alerts`

## IoT Gateway (Port 8081) - TO IMPLEMENT

### Responsibilities
- Receive data from IoT sensors and drones
- Queue sensor data to Redis
- Upload drone images to S3

### Expected Endpoints

#### POST `/api/sensors/data`
Receive sensor data and queue to Redis
```json
{
  "user_id": "1",
  "timestamp": "2023-12-01T14:30:22Z",
  "measurements": {
    "temperature": 24.5,
    "humidity": 65.2,
    "soil_moisture": 45.3
  }
}
```

Response:
```json
{
  "success": true,
  "message": "Sensor data queued successfully"
}
```

#### POST `/api/drones/image`
Receive drone image, upload to S3, and queue metadata to Redis
- **Content-Type**: `multipart/form-data`
- **Fields**:
  - `image`: Image file (JPEG/PNG)
  - `drone_id`: Drone identifier
  - `timestamp`: Capture timestamp

Response:
```json
{
  "success": true,
  "s3_path": "drone-images/2023/12/01/drone_001_143022.jpg",
  "message": "Image uploaded and queued successfully"
}
```

### Internal Operations
1. **Sensor Data**: Validate → Queue to Redis `sensor_data`
2. **Drone Images**: Upload to S3 → Queue metadata to Redis `drone_data`

## Database Schema (AWS RDS PostgreSQL)

### RDS Configuration
- **Engine**: PostgreSQL 15.8
- **Instance**: Multi-AZ for high availability
- **Storage**: GP3 SSD with encryption
- **Backup**: 7-day retention, automated backups
- **Security**: VPC isolated, accessed only from Fargate

### Database Tables

#### users
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT NOT NULL
);
```

#### parameters
```sql
CREATE TABLE parameters (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    temperature REAL,
    humidity REAL,
    soil_moisture REAL,
    min_temperature REAL,
    max_temperature REAL,
    min_humidity REAL,
    max_humidity REAL,
    min_soil_moisture REAL,
    max_soil_moisture REAL
);
```

#### sensor_data
```sql
CREATE TABLE sensor_data (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    timestamp TIMESTAMP NOT NULL,
    measure TEXT NOT NULL,
    value REAL NOT NULL
);
```

#### drone_images
```sql
CREATE TABLE drone_images (
    id SERIAL PRIMARY KEY,
    drone_id VARCHAR(255),
    raw_s3_key VARCHAR(500),
    processed_s3_key VARCHAR(500),
    field_status VARCHAR(50) DEFAULT 'unknown',
    analysis_confidence REAL DEFAULT 0.0,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    analyzed_at TIMESTAMP
);
```

## Environment Configuration (AWS Serverless)

### ECS Fargate Container Environment
The Processing Engine runs as a containerized service with environment variables:

```bash
# AWS Configuration
AWS_DEFAULT_REGION=us-east-1

# SQS Configuration  
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/account/agrosynchro-processing-queue

# S3 Configuration
RAW_IMAGES_BUCKET=agrosynchro-raw-images
PROCESSED_IMAGES_BUCKET=agrosynchro-processed-images

# RDS Configuration
DB_HOST=agrosynchro-postgres.xxxxx.rds.amazonaws.com
DB_PORT=5432
DB_NAME=agrosynchro
DB_USER=agro
DB_PASSWORD=[from AWS Secrets Manager]
```

### Infrastructure Access Patterns

#### Data Flow
1. **IoT Sensors** → API Gateway `/messages` → SQS → Fargate Processing
2. **Drone Images** → API Gateway `/api/drones/image` → Lambda → S3 → SQS → Fargate Analysis  
3. **Dashboard Queries** → ALB → Fargate → RDS → Response
4. **Health Checks** → ALB `/health` → Fargate → RDS connectivity test

#### Security Architecture
- **Network**: VPC with private/public subnet isolation
- **Data**: Encryption at rest (RDS, S3, SQS) and in transit (HTTPS)
- **Access**: IAM roles with least privilege (LabRole for AWS Academy)
- **Monitoring**: CloudWatch logs and metrics for all services
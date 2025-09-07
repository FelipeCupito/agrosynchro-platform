# AgroSynchro - API Documentation & Service Specifications

## Architecture Overview

```
[IoT Sensors/Drones] → [IoT Gateway] → [Message Queue] → [Processing Engine] → [Web Service] → [Frontend]
                                           ↓
                                    [Database Storage]
```

## Services & Ports

| Service | Port | Protocol | Status | Responsibility |
|---------|------|----------|---------|----------------|
| Message Queue (Redis) | 6379 | TCP | ✅ Implemented | Message routing and queuing |
| Processing Engine API | 8080 | HTTP/REST | ✅ Implemented | Data analysis and processing |
| Web Dashboard Backend | 3000 | HTTP/REST | ✅ Basic Setup | Backend API for dashboard |
| Web Dashboard Frontend | 3001 | HTTP | 🔄 To Implement | User interface |
| IoT Gateway | 8081 | HTTP/REST | ✅ Basic Setup | IoT device communication |

### Development Tools
| Tool | Port | Description |
|------|------|-------------|
| Mocks | 9000 | IoT data generators and testing tools |
| MinIO (S3 Local) | 9000-9001 | Local S3-compatible storage |

## Message Queue Schemas

### Redis Queue Names
- `sensor_data` - Environmental sensor readings
- `drone_data` - Drone imagery and telemetry
- `alerts` - System alerts and notifications

### Message Schemas

#### Sensor Data Message
```json
{
  "sensor_id": "TEMP_001",
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

## Processing Engine API (Port 8080)

### Base URL: `http://localhost:8080`

### Health Endpoint

#### GET `/health`
Health check endpoint
```json
{
  "status": "healthy",
  "timestamp": "2023-12-01T14:30:22Z",
  "uptime_seconds": 3600,
  "database_connected": true
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
  "sensor_id": "TEMP_001",
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

## Database Schema (Processing Engine Responsibility)

### Processing Engine Database (SQLite)

#### sensor_data
```sql
CREATE TABLE sensor_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sensor_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    temperature REAL,
    humidity REAL,
    soil_moisture REAL,
    processed_at TEXT NOT NULL
);
```

#### image_analyses
```sql
CREATE TABLE image_analyses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drone_id TEXT NOT NULL,
    s3_path TEXT NOT NULL,
    analyzed_at TEXT NOT NULL,
    field_status TEXT NOT NULL -- excellent, good, fair, poor, critical
);
```

#### alert_config
```sql
CREATE TABLE alert_config (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    alert_name TEXT NOT NULL,
    sensor_type TEXT NOT NULL,
    min_value REAL,
    max_value REAL,
    enabled BOOLEAN DEFAULT 1,
    created_at TEXT NOT NULL
);
```

## Environment Configuration

All services use centralized environment configuration from root `.env` file.

### Development (.env)
```bash
# Redis Configuration
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=agroredispass123

# Processing Engine
PROCESSING_ENGINE_HOST=processing-engine
PROCESSING_ENGINE_PORT=8080

# S3 Configuration (Local MinIO)
S3_ENDPOINT=http://minio:9000
S3_BUCKET=agrosynchro-drone-images
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=agrosynchro
AWS_SECRET_ACCESS_KEY=agrosynchro123

# Database
DATABASE_PATH=/data/processing.db

# IoT Gateway & Web Service (when implemented)
IOT_GATEWAY_HOST=iot-gateway
IOT_GATEWAY_PORT=8081
WEB_SERVICE_HOST=web-service
WEB_SERVICE_PORT=3000

ENVIRONMENT=development
```

### Production (.env.production)
```bash
# Redis Configuration (AWS ElastiCache or ECS)
REDIS_HOST=agrosynchro-redis.cluster.local
REDIS_PORT=6379
REDIS_PASSWORD=your-secure-redis-password

# Processing Engine (AWS ECS service)
PROCESSING_ENGINE_HOST=agrosynchro-processing.cluster.local
PROCESSING_ENGINE_PORT=8080

# S3 Configuration (Real AWS S3)
S3_ENDPOINT=
S3_BUCKET=agrosynchro-drone-images-prod
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-aws-key
AWS_SECRET_ACCESS_KEY=your-aws-secret

# Services (AWS Load Balancer endpoints)
IOT_GATEWAY_HOST=agrosynchro-iot.cluster.local
WEB_SERVICE_HOST=agrosynchro-web.cluster.local

ENVIRONMENT=production
```
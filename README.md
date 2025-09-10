# AgroSynchro - Development Setup

## Environment Configuration

### 1. Setup Environment Files
```bash
# Development (already configured)
cp .env .env.local  # Optional: for local overrides

# Production (when deploying)
cp .env.production .env
```

### 2. Quick Start
```bash
# Start all services in development mode (uses .env)
docker-compose -f docker-compose.dev.yml up -d

# Start with production config (uses .env.production)
docker-compose -f docker-compose.dev.yml --env-file .env.production up -d

# View logs
docker-compose -f docker-compose.dev.yml logs -f

# Stop all services
docker-compose -f docker-compose.dev.yml down
```

### 3. Service URLs
- **Redis**: `localhost:6379` (password: `agroredispass123`)
- **Processing Engine API**: `http://localhost:8080`
- **IoT Gateway API**: `http://localhost:8081`
- **Web Dashboard Backend**: `http://localhost:3000`
- **Mocks Tools**: `http://localhost:9002`
- **MinIO S3 (Dev)**: `http://localhost:9000` (user: `agrosynchro`, pass: `agrosynchro123`)
- **MinIO Console**: `http://localhost:9001`

### 4. Health Checks
```bash
# Check all services
curl http://localhost:8080/ping  # Processing Engine
curl http://localhost:8081/ping  # IoT Gateway
curl http://localhost:3000/ping  # Web Dashboard Backend
curl http://localhost:9002/ping  # Mocks Tools

# Check Redis
docker exec agrosynchro-redis redis-cli -a agroredispass123 ping

# Check MinIO
curl http://localhost:9000/minio/health/live
```

## Individual Service Development

### Message Queue Only
```bash
cd services/message-queue
docker-compose up -d
```

### Processing Engine Only
```bash
# Create network first
docker network create agrosynchro

# Start message queue
cd services/message-queue
docker-compose up -d

# Start processing engine
cd ../processing-engine
docker-compose up -d
```

## Current Service Status

All services are currently **basic/ping-only**:

- ✅ **Redis**: Fully functional message queue
- ✅ **Processing Engine**: Basic `/ping` endpoint (APIs to be implemented)
- ✅ **IoT Gateway**: Basic `/ping` endpoint (APIs to be implemented) 
- ✅ **Web Dashboard Backend**: Basic `/ping` endpoint (APIs to be implemented)
- ✅ **Mocks**: Basic `/ping` endpoint (test data generators to be implemented)
- ✅ **MinIO**: Fully functional S3-compatible storage

## MinIO Web Console

Access MinIO's web interface to manage files:

1. Go to: `http://localhost:9001`
2. Login with:
   - **Username**: `agrosynchro`
   - **Password**: `agrosynchro123`
3. Create buckets, upload files, etc.

## Next Steps for Development

Each service needs implementation beyond the basic `/ping` endpoint:

1. **Processing Engine**: Implement sensor data processing and image analysis APIs
2. **IoT Gateway**: Implement data ingestion endpoints for sensors and drones
3. **Web Dashboard**: Implement dashboard APIs that consume Processing Engine data
4. **Mocks**: Implement test data generators for sensors and drone images

## Development Notes

- **All services** communicate through the `agrosynchro` Docker network
- **MinIO** provides local S3-compatible storage (no AWS needed for development)
- **Environment variables** are centralized in `.env` file
- **Individual deployment** possible for each service (AWS-style)
- **Mocks** directory contains testing utilities (separate from services)

## Troubleshooting

### Container Issues
```bash
# Check container status
docker-compose -f docker-compose.dev.yml ps

# View specific service logs
docker-compose -f docker-compose.dev.yml logs processing-engine

# Restart specific service
docker-compose -f docker-compose.dev.yml restart processing-engine
```

### Network Issues
```bash
# Check network
docker network ls | grep agrosynchro

# Inspect network
docker network inspect agrosynchro_agrosynchro
```

### Data Cleanup
```bash
# Remove all data (careful!)
docker-compose -f docker-compose.dev.yml down -v

# Remove only containers
docker-compose -f docker-compose.dev.yml down
```

# Conexión a Instancias Privadas via Bastion Host

## Prerequisitos
- Bastion Host desplegado en subred pública
- Tu clave SSH (.pem) configurada
- IPs del Bastion y instancias privadas

## Conexión SSH Directa

### Comando básico:
```bash
ssh -i "tu-key.pem" -J ec2-user@<bastion-ip> ec2-user@<private-instance-ip>
```

### Ejemplo real:
```bash
ssh -i "mykey.pem" -J ec2-user@3.15.123.45 ec2-user@10.0.2.10
```

## Transferencia de Archivos (SCP)

### Subir archivo a instancia privada:
```bash
scp -i "tu-key.pem" -o ProxyJump=ec2-user@<bastion-ip> archivo.txt ec2-user@<private-instance-ip>:~/
```

### Descargar archivo desde instancia privada:
```bash
scp -i "tu-key.pem" -o ProxyJump=ec2-user@<bastion-ip> ec2-user@<private-instance-ip>:~/archivo.txt ./
```

### Ejemplos reales:
```bash
# Subir docker-compose.yml
scp -i "mykey.pem" -o ProxyJump=ec2-user@3.15.123.45 docker-compose.yml ec2-user@10.0.2.10:~/

# Descargar logs
scp -i "mykey.pem" -o ProxyJump=ec2-user@3.15.123.45 ec2-user@10.0.2.10:~/app.log ./
```


## Comandos de Deploy Rápido

```bash
# 1. Conectar a Web Server
ssh -i "mykey.pem" -J ec2-user@<bastion-ip> ec2-user@10.0.2.10

# 2. Clonar repositorio
git clone https://github.com/tu-usuario/iot-platform.git

# 3. Levantar servicios
cd iot-platform
docker-compose up -d

# 4. Verificar estado
docker-compose ps
```
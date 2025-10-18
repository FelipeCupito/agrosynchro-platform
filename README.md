# AgroSynchro - Setup Local

## Pasos para levantar la infraestructura local:

1. **Levantar LocalStack:**
   ```bash
   docker-compose up -d
   ```

2. **Verificar LocalStack:**
   ```bash
   curl http://localhost:4566/_localstack/health
   ```

3. **Ir a terraform:**
   ```bash
   cd terraform
   ```

4. **Inicializar terraform:**
   ```bash
   terraform init
   ```

5. **Crear workspace local:**
   ```bash
   terraform workspace new local
   # o si ya existe:
   terraform workspace select local
   ```

6. **Aplicar infraestructura:**
   ```bash
   terraform apply -var-file="environments/local/terraform.tfvars"
   ```

7. **Probar endpoints:**
   ```bash
   # Ping
   curl -X GET http://localhost:4566/restapis/[API_ID]/local/_user_request_/ping
   
   # Messages
   curl -X POST http://localhost:4566/restapis/[API_ID]/local/_user_request_/messages \
     -H "Content-Type: application/json" \
     -d '{"message": "test from sensor"}'
   ```
# CONTEXTO DEL PROYECTO - TP TERRAFORM RECUPERATORIO

## ESTADO ACTUAL DEL PROYECTO

### Situación Académica
- **Tipo**: Recuperatorio (TP desaprobado previamente)
- **Objetivo principal**: Aprobar el TP de Infraestructura como Código
- **Premios disponibles**: 
  - $1000 premio base por aprobar
  - $1000 premio bonus por mejor trabajo
- **Entorno**: AWS Academy (limitaciones de LabRole)

### Arquitectura Actual (FUNCIONANDO)
```
Internet → API Gateway → Lambda Functions
                      ↘
                       SQS → Fargate Workers
                      ↗         ↓
                    S3 ←→ RDS PostgreSQL
```

### Estado de la Infraestructura
- ✅ **8 módulos implementados**: 6 custom + 2 externos (VPC, RDS)
- ✅ **S3 optimizado**: 3 buckets (frontend, raw-images, processed-images)
- ✅ **Terraform validate**: SUCCESS
- ✅ **ALB eliminado**: Workers puros, ahorro $20/mes
- ✅ **11 funciones Terraform** implementadas
- ✅ **4 meta-argumentos** implementados

## REQUISITOS ACADÉMICOS (CUMPLIMIENTO)

### ✅ Módulos (COMPLETO)
- [x] **Mínimo 1 módulo personalizado**: 6 implementados
- [x] **Mínimo 1 módulo externo**: 2 implementados (VPC, RDS)

### ✅ Variables y Outputs (COMPLETO)
- [x] Parametrización efectiva sin defaults inseguros
- [x] Outputs documentados y útiles

### ✅ Funciones Terraform (11/4 REQUERIDAS)
1. `split()` - Extracción de hostname desde endpoints
2. `tostring()` - Conversión de tipos para puertos  
3. `md5()` - Hashing para ETags de S3
4. `jsonencode()` - Políticas IAM y configuraciones
5. `length()` - Cálculos de arrays y listas
6. `lookup()` - Mapeo de tipos de archivos
7. `filemd5()` - Checksums de archivos locales
8. `sha1()` - Hashing para redeployments
9. `slice()` - Selección de availability zones
10. `formatdate()` - Timestamps para tags
11. `timestamp()` - Marcas temporales dinámicas

### ✅ Meta-argumentos (4/3 REQUERIDAS)
1. **depends_on**: Control explícito de dependencias entre módulos
2. **for_each**: Tracking dinámico de componentes de infraestructura  
3. **count**: Recursos condicionales (read replica, permisos Lambda)
4. **lifecycle**: `create_before_destroy` para recursos críticos

### ✅ Principio DRY (COMPLETO)
- [x] Reutilización de variables y locals
- [x] Módulos sin duplicación

## CONFIGURACIÓN TÉCNICA ACTUAL

### S3 Buckets (3)
1. **frontend**: Público, sin versionado, hosting estático
2. **raw-images**: Privado, sin versionado, encriptado, lifecycle a Glacier 180d
3. **processed-images**: Privado, versionado, encriptado, lifecycle IA/Glacier

### Módulos Externos (2)
- `terraform-aws-modules/vpc/aws ~> 5.0`: Networking enterprise-grade
- `terraform-aws-modules/rds/aws 6.1.1`: PostgreSQL con mejores prácticas

### Módulos Custom (6)
- `lambda/`: Funciones serverless para API y procesamiento
- `s3/`: Buckets optimizados por caso de uso
- `sqs/`: Colas de mensajes y dead letter queue  
- `api-gateway/`: REST API con integración Lambda/SQS
- `cognito/`: Autenticación OAuth
- `fargate/`: Workers containerizados para procesamiento

### Variables Críticas
```hcl
aws_region = "us-east-1"
vpc_cidr_block = "10.0.0.0/16" 
db_username = "agro"
db_password = "SENSITIVE_NO_DEFAULT"
db_instance_class = "db.t3.micro"
```

## RESTRICCIONES Y LIMITACIONES

### AWS Academy
- **Solo LabRole**: No se pueden crear roles IAM personalizados
- **Sin state remoto**: Limitación del sandbox educativo
- **Región fija**: Generalmente us-east-1
- **Instancias limitadas**: db.t3.micro, Fargate 512/1024

### Arquitectura
- **Sin ALB**: Fargate como workers puros (optimización implementada)
- **Multi-AZ**: Configurado automáticamente con slice() de AZs
- **Encriptación**: AES256 donde es necesario
- **Networking**: VPC con subnets públicas/privadas/database

## ARCHIVOS CLAVE

### Terraform Core
- `terraform/main.tf`: Configuración principal y llamadas a módulos
- `terraform/variables.tf`: Variables sin defaults inseguros
- `terraform/terraform.tfvars`: Valores de configuración
- `terraform/version.tf`: Versiones de Terraform y providers
- `terraform/outputs.tf`: Outputs limpios y útiles

### Documentación
- `terraform/README.md`: Documentación académica completa
- `PROYECTO_CONTEXTO.md`: Este archivo de contexto

### Módulos Críticos
- `terraform/modules/s3/main.tf`: Configuración optimizada de buckets
- `terraform/modules/lambda/main.tf`: Funciones serverless
- `terraform/modules/fargate/main.tf`: Workers sin ALB

## PRÓXIMOS PASOS POTENCIALES

### Si se requieren cambios adicionales:
1. **Testing adicional**: Terraform plan/apply en AWS Academy
2. **Optimización de costos**: Revisar sizing de instancias
3. **Documentación extra**: Diagramas de arquitectura si se requieren
4. **Validación final**: Revisión completa antes de entrega

### Si surgen errores:
1. **Internet requerido**: Para descargar módulos externos
2. **Credentials**: Verificar AWS CLI configurado con LabRole
3. **Región**: Confirmar us-east-1 o región asignada del lab

## COMANDOS DE VALIDACIÓN

```bash
cd terraform/
terraform init      # Descargar módulos externos
terraform validate  # ✅ PASANDO
terraform plan      # Revisar cambios
terraform apply     # Solo si es necesario
```

## PUNTOS DE CALIDAD PARA EL BONUS

1. **2 módulos externos** (más del mínimo requerido)
2. **Arquitectura enterprise-grade** con mejores prácticas
3. **Optimización de costos** (eliminación ALB, lifecycle policies)
4. **Seguridad avanzada** (encriptación, subnets privadas, SGs)
5. **Código limpio** siguiendo principio DRY
6. **Documentación completa** con explicaciones técnicas
7. **11 funciones Terraform** (mucho más del mínimo)
8. **Multi-AZ dinámico** con discovery automático

## STATUS: LISTO PARA ENTREGA

El proyecto cumple TODOS los requisitos académicos y está optimizado para competir por el premio bonus de $1000.
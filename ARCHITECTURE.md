# Arquitectura del Proyecto (Terraform)

Este documento describe la estructura del código Terraform utilizado para desplegar la infraestructura de `agrosynchro` en AWS.

## Descripción de Módulos

El proyecto utiliza una [arquitectura modular](https://developer.hashicorp.com/terraform/language/modules) para organizar y reutilizar la configuración. El archivo `main.tf` de la raíz actúa como el orquestador principal, instanciando los siguientes módulos:

  * `modules/networking`:

      * **Propósito:** Crea la base de la red.
      * **Recursos Clave:** Define la **VPC**, las **Subredes** (Públicas, Privadas y de Base de Datos) distribuidas en dos Zonas de Disponibilidad, **Route Tables**, un **Internet Gateway (IGW)** para las subredes públicas, y **NAT Gateways** para que las subredes privadas tengan salida a internet. También incluye el **VPC Endpoint** para S3.

  * `modules/s3`:

      * **Propósito:** Gestiona todo el almacenamiento de objetos.
      * **Recursos Clave:** Crea tres buckets:
        1.  `frontend`: Bucket público con *static website hosting* habilitado para la aplicación web.
        2.  `raw_images`: Bucket privado para imágenes crudas.
        3.  `processed_images`: Bucket privado para imágenes procesadas.

  * `modules/rds`:

      * **Propósito:** Despliega la base de datos relacional.
      * **Recursos Clave:** Crea una instancia **RDS PostgreSQL** (`aws_db_instance`) configurada como `multi_az = true` para alta disponibilidad. También crea una **Réplica de Lectura (Read Replica)** en la AZ opuesta para descargar consultas. Se ejecuta en las subredes de Base de Datos.

  * `modules/sqs`:

      * **Propósito:** Provee un sistema de colas de mensajes para desacoplar servicios.
      * **Recursos Clave:** Crea una cola **SQS** estándar para recibir mensajes (ej. desde la API) y una **Dead Letter Queue (DLQ)** asociada para manejar mensajes fallidos.

  * `modules/lambda`:

      * **Propósito:** Define todas las funciones de cómputo *serverless*.
      * **Recursos Clave:** Empaqueta y despliega múltiples funciones Lambda. Las funciones principales (API, reports, etc.) se configuran para ejecutarse *dentro* de la VPC (en las subredes privadas) para tener acceso seguro a la base de datos RDS.

  * `modules/fargate`:

      * **Propósito:** Ejecuta el servicio de procesamiento de larga duración.
      * **Recursos Clave:** Define un clúster de **ECS** y un servicio de **Fargate** (`processing-engine`).

  * `modules/api-gateway`:

      * **Propósito:** Actúa como la puerta de entrada (frontend) para toda la lógica de backend.
      * **Recursos Clave:** Define el `aws_api_gateway_rest_api` y sus *endpoints* (`/users`, `/reports`, `/messages`, etc.). Configura las integraciones para cada ruta, apuntando a:
          * **AWS Lambda** (para la mayoría de las rutas de la API).
          * **AWS SQS** (para la ruta `/messages`).

  * `modules/cognito`:

      * **Propósito:** Maneja la autenticación y gestión de usuarios.
      * **Recursos Clave:** Crea un **Cognito User Pool** y un **User Pool Client** para permitir el registro y login de usuarios a través de la interfaz web.

-----

## Funciones y Meta-Argumentos Clave

Para que la infraestructura sea dinámica y robusta, se utilizan varias funciones y meta-argumentos de Terraform.

### Funciones (Functions)

Las funciones se usan para transformar o combinar datos.

  * `jsonencode()`:

      * **Uso:** Convierte una estructura de HCL (como un `map` o `list`) en una cadena de texto JSON.
      * **Ejemplo (`modules/fargate/main.tf`):**
        ```terraform
        container_definitions = jsonencode([
          {
            name  = "processing-engine"
            image = "${aws_ecr_repository.processing_engine.repository_url}:latest"
            # ...
          }
        ])
        ```

  * `split()`:

      * **Uso:** Divide una cadena de texto en una lista, usando un delimitador.
      * **Ejemplo (`main.tf`):**
        ```terraform
        module "fargate" {
          # ...
          rds_endpoint = split(":", module.rds.db_instance_endpoint)[0]
        }
        ```
        *En este caso, se usa para quitar el puerto (ej. `:5432`) del *endpoint* de RDS y pasar solo el hostname al contenedor de Fargate.*

  * `fileset()` y `filemd5()`:

      * **Uso:** `fileset` genera una lista de archivos en un directorio, y `filemd5` calcula el hash de un archivo.
      * **Ejemplo (`modules/s3/main.tf`):**
        ```terraform
        resource "aws_s3_object" "frontend_files" {
          for_each = setsubtract(fileset("${path.root}/../services/web-dashboard/frontend/build", "**/*"), ["env.js"])
          # ...
          etag = filemd5("${path.root}/../services/web-dashboard/frontend/build/${each.value}")
        }
        ```
        *Esto sube todos los archivos del *build* del frontend a S3 y usa el hash `etag` para reemplazar solo los archivos que cambiaron.*

### Meta-Argumentos

Los meta-argumentos cambian el comportamiento de cómo Terraform crea, gestiona o destruye los recursos.

  * `depends_on`:

      * **Uso:** Fuerza a Terraform a esperar a que un recurso o módulo se cree antes de intentar crear otro. Se usa para dependencias implícitas.
      * **Ejemplo (`main.tf`):**
        ```terraform
        module "lambda" {
          source = "./modules/lambda"
          # ...
          vpc_id            = module.networking.vpc_id
          private_subnets   = module.networking.private_subnet_ids
          db_host           = split(":", module.rds.db_instance_endpoint)[0]
          
          depends_on = [module.s3, module.networking, module.rds]
        }
        ```
        *Aunque Terraform puede inferir la dependencia de `networking` y `rds` (porque se usan sus `outputs`), `depends_on` se usa aquí para asegurar explícitamente que la red, la DB y S3 estén 100% listos antes de intentar crear las Lambdas.*

  * `count`:

      * **Uso:** Crea múltiples copias de un recurso (o módulo) basado en un número.
      * **Ejemplo (`modules/networking/main.tf`):**
        ```terraform
        resource "aws_subnet" "public" {
          count = length(var.public_subnet_cidrs)

          vpc_id     = aws_vpc.main.id
          cidr_block = var.public_subnet_cidrs[count.index]
          # ...
        }
        ```
        *Esto crea tantas subredes públicas como CIDRs se hayan definido en la variable (en tu caso, 2, una para cada AZ).*

  * `for_each`:

      * **Uso:** Similar a `count`, pero itera sobre un `map` o `set` de strings. Es más flexible porque el `key` del ítem se usa en el identificador del recurso.
      * **Ejemplo (`modules/s3/main.tf`):**
        ```terraform
        resource "aws_s3_object" "frontend_files" {
          for_each = setsubtract(fileset(...), ["env.js"])

          bucket = aws_s3_bucket.frontend.id
          key    = each.value
          source = "${path.root}/../services/web-dashboard/frontend/build/${each.value}"
          # ...
        }
        ```
        *Esto crea un recurso `aws_s3_object` por *cada archivo* encontrado en el `fileset`, usando el nombre del archivo (`each.value`) como `key`.*

  * `lifecycle`:

      * **Uso:** Permite un control detallado sobre el ciclo de vida del recurso.
      * **Ejemplo (`modules/fargate/main.tf`):**
        ```terraform
        resource "aws_ecs_service" "processing_engine" {
          # ...
          desired_count = var.fargate_desired_count

          lifecycle {
            ignore_changes = [desired_count]
          }
        }
        ```
        *Esto es **muy importante**: le dice a Terraform que *ignore* si el `desired_count` (número de tareas) cambia. Esto es fundamental para permitir que el **Auto Scaling** de AWS escale el servicio hacia arriba o abajo sin que Terraform, en el próximo `apply`, intente volver a ponerlo en el valor original.*
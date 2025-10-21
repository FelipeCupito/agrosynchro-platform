# =============================================================================
# RANDOM STRING FOR BUCKET NAMING
# =============================================================================

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# IAM ROLES FOR S3 ACCESS - COMMENTED OUT FOR AWS ACADEMY LIMITATIONS
# =============================================================================

# NOTE: In AWS Academy labs, IAM role creation is often restricted
# You may need to use existing roles or request IAM permissions

/*
# IAM role for Lambda to access S3
resource "aws_iam_role" "lambda_s3_role" {
  name = "${var.project_name}-lambda-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-s3-role"
    Environment = var.environment
  }
}

# IAM policy for Lambda S3 access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.project_name}-lambda-s3-policy"
  role = aws_iam_role.lambda_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.raw_images.arn}/*",
          "${aws_s3_bucket.processed_images.arn}/*",
          "${aws_s3_bucket.images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_images.arn,
          aws_s3_bucket.processed_images.arn,
          aws_s3_bucket.images.arn
        ]
      }
    ]
  })
}

# Attach basic Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_s3_role.name
}

# IAM role for Fargate to access S3
resource "aws_iam_role" "fargate_s3_role" {
  name = "${var.project_name}-fargate-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fargate-s3-role"
    Environment = var.environment
  }
}

# IAM policy for Fargate S3 access
resource "aws_iam_role_policy" "fargate_s3_policy" {
  name = "${var.project_name}-fargate-s3-policy"
  role = aws_iam_role.fargate_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.raw_images.arn}/*",
          "${aws_s3_bucket.processed_images.arn}/*",
          "${aws_s3_bucket.images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_images.arn,
          aws_s3_bucket.processed_images.arn,
          aws_s3_bucket.images.arn
        ]
      }
    ]
  })
}
*/

# =============================================================================
# FRONTEND BUCKET - Static Website Hosting (público)
# =============================================================================
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-frontend"
    Purpose     = "static_frontend"
    Environment = var.environment
  }
}

# Habilitar hosting web estático
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Desbloquear acceso público
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  restrict_public_buckets = false
  ignore_public_acls      = false
}

# Política pública (lectura abierta)
data "aws_iam_policy_document" "frontend_public" {
  statement {
    sid       = "PublicReadGetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_public" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_public.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# Subida automática de archivos del frontend build (excluyendo env.js)
resource "aws_s3_object" "frontend_files" {
  for_each = setsubtract(fileset("${path.root}/../services/web-dashboard/frontend/build", "**/*"), ["env.js"])

  bucket = aws_s3_bucket.frontend.id
  key    = each.value
  source = "${path.root}/../services/web-dashboard/frontend/build/${each.value}"

  etag = filemd5("${path.root}/../services/web-dashboard/frontend/build/${each.value}")

  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "json" = "application/json",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "svg"  = "image/svg+xml",
    "ico"  = "image/x-icon"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "text/plain")
}

# =============================================================================
# RAW IMAGES BUCKET - Drone Raw Images (privado)
# =============================================================================

resource "aws_s3_bucket" "raw_images" {
  bucket = "${var.project_name}-raw-images-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-raw-images"
    Purpose     = "drone_raw_images"
    Environment = var.environment
  }
}

# Bloquear cualquier acceso público
resource "aws_s3_bucket_public_access_block" "raw_images" {
  bucket                  = aws_s3_bucket.raw_images.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

# Versionado para evitar pérdida de archivos
resource "aws_s3_bucket_versioning" "raw_images_versioning" {
  bucket = aws_s3_bucket.raw_images.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación del bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_images_encryption" {
  bucket = aws_s3_bucket.raw_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# PROCESSED IMAGES BUCKET - Processed Drone Images (privado)
# =============================================================================

resource "aws_s3_bucket" "processed_images" {
  bucket = "${var.project_name}-processed-images-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-processed-images"
    Purpose     = "drone_processed_images"
    Environment = var.environment
  }
}

# Bloquear cualquier acceso público
resource "aws_s3_bucket_public_access_block" "processed_images" {
  bucket                  = aws_s3_bucket.processed_images.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

# Versionado para evitar pérdida de archivos
resource "aws_s3_bucket_versioning" "processed_images_versioning" {
  bucket = aws_s3_bucket.processed_images.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación del bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "processed_images_encryption" {
  bucket = aws_s3_bucket.processed_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# IMAGES BUCKET - Drone Images (privado)
# =============================================================================

resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-images-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-images"
    Purpose     = "drone_images_private"
    Environment = var.environment
  }
}

# Bloquear cualquier acceso público
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

# Versionado para evitar pérdida de archivos
resource "aws_s3_bucket_versioning" "images_versioning" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación del bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "images_encryption" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy opcional (por ejemplo, borrar luego de 90 días)
resource "aws_s3_bucket_lifecycle_configuration" "images_lifecycle" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "cleanup_old_images"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "frontend_bucket_name" {
  value       = aws_s3_bucket.frontend.bucket
  description = "Nombre del bucket donde se hostea el frontend"
}

output "frontend_bucket_website_endpoint" {
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
  description = "URL de hosting web estático del frontend"
}

output "images_bucket_name" {
  value       = aws_s3_bucket.images.bucket
  description = "Nombre del bucket donde se guardan las imágenes de drones (privado)"
}
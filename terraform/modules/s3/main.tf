# =============================================================================
# S3 BUCKETS MODULE - AGROSYNCHRO
# =============================================================================
# Módulo para crear buckets S3 para el procesamiento de imágenes de drones
# - Raw Images: Imágenes sin procesar (desde drones)
# - Processed Images: Imágenes ya procesadas (desde Fargate)
# =============================================================================

# Random suffix para nombres únicos de buckets
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# RAW IMAGES BUCKET - Imágenes sin procesar
# =============================================================================

resource "aws_s3_bucket" "raw_images" {
  bucket = "${var.project_name}-raw-images-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-raw-images"
    Purpose     = "raw_drone_images"
    Environment = var.environment
  }
}

# Versioning para raw images
resource "aws_s3_bucket_versioning" "raw_images_versioning" {
  bucket = aws_s3_bucket.raw_images.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption para raw images
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_images_encryption" {
  bucket = aws_s3_bucket.raw_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public access block para raw images
resource "aws_s3_bucket_public_access_block" "raw_images_pab" {
  bucket = aws_s3_bucket.raw_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy para raw images (delete after 30 days)
resource "aws_s3_bucket_lifecycle_configuration" "raw_images_lifecycle" {
  bucket = aws_s3_bucket.raw_images.id

  rule {
    id     = "delete_old_raw_images"
    status = "Enabled"
    
    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# =============================================================================
# PROCESSED IMAGES BUCKET - Imágenes procesadas
# =============================================================================

resource "aws_s3_bucket" "processed_images" {
  bucket = "${var.project_name}-processed-images-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-processed-images"
    Purpose     = "processed_drone_images"
    Environment = var.environment
  }
}

# Versioning para processed images
resource "aws_s3_bucket_versioning" "processed_images_versioning" {
  bucket = aws_s3_bucket.processed_images.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption para processed images
resource "aws_s3_bucket_server_side_encryption_configuration" "processed_images_encryption" {
  bucket = aws_s3_bucket.processed_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public access block para processed images
resource "aws_s3_bucket_public_access_block" "processed_images_pab" {
  bucket = aws_s3_bucket.processed_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy para processed images (keep longer)
resource "aws_s3_bucket_lifecycle_configuration" "processed_images_lifecycle" {
  bucket = aws_s3_bucket.processed_images.id

  rule {
    id     = "archive_old_processed_images"
    status = "Enabled"
    
    filter {
      prefix = ""
    }

    # Move to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 1 year
    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# =============================================================================
# IAM POLICIES FOR BUCKET ACCESS
# =============================================================================

# Policy document for Lambda to access raw images bucket
data "aws_iam_policy_document" "lambda_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.raw_images.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.raw_images.arn
    ]
  }
}

# Policy document for Fargate to access both buckets
data "aws_iam_policy_document" "fargate_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.raw_images.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      "${aws_s3_bucket.processed_images.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.raw_images.arn,
      aws_s3_bucket.processed_images.arn
    ]
  }
}

# IAM role for Lambda
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
    Name = "${var.project_name}-lambda-s3-role"
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach S3 policy to Lambda role
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.project_name}-lambda-s3-access"
  role = aws_iam_role.lambda_s3_role.id
  policy = data.aws_iam_policy_document.lambda_s3_policy.json
}

# IAM role for Fargate
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
    Name = "${var.project_name}-fargate-s3-role"
  }
}

# Attach S3 policy to Fargate role
resource "aws_iam_role_policy" "fargate_s3_access" {
  name = "${var.project_name}-fargate-s3-access"
  role = aws_iam_role.fargate_s3_role.id
  policy = data.aws_iam_policy_document.fargate_s3_policy.json
}
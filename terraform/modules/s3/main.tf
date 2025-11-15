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
          "${aws_s3_bucket.processed_images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_images.arn,
          aws_s3_bucket.processed_images.arn
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
          "${aws_s3_bucket.processed_images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_images.arn,
          aws_s3_bucket.processed_images.arn
        ]
      }
    ]
  })
}
*/

# =============================================================================
# S3 BUCKETS - Configurable with for_each
# =============================================================================
resource "aws_s3_bucket" "buckets" {
  for_each = var.buckets
  
  bucket = "${var.project_name}-${each.key}-${random_string.bucket_suffix.result}"

  tags = merge({
    Name        = "${var.project_name}-${each.key}"
    Purpose     = each.value.purpose
    Environment = var.environment
  }, var.additional_tags)
}

# =============================================================================
# PUBLIC ACCESS CONFIGURATION
# =============================================================================
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = var.buckets
  
  bucket                  = aws_s3_bucket.buckets[each.key].id
  block_public_acls       = !each.value.public_read
  block_public_policy     = !each.value.public_read
  restrict_public_buckets = !each.value.public_read
  ignore_public_acls      = !each.value.public_read
}

# =============================================================================
# WEBSITE CONFIGURATION (conditional)
# =============================================================================
resource "aws_s3_bucket_website_configuration" "website" {
  for_each = { for k, v in var.buckets : k => v if v.enable_website }
  
  bucket = aws_s3_bucket.buckets[each.key].id

  index_document {
    suffix = var.website_index_document
  }

  error_document {
    key = var.website_error_document
  }
}

# =============================================================================
# PUBLIC READ POLICY (conditional)
# =============================================================================
data "aws_iam_policy_document" "public_read" {
  for_each = { for k, v in var.buckets : k => v if v.public_read }
  
  statement {
    sid       = "PublicReadGetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.buckets[each.key].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  for_each = { for k, v in var.buckets : k => v if v.public_read }
  
  bucket = aws_s3_bucket.buckets[each.key].id
  policy = data.aws_iam_policy_document.public_read[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.buckets]
}

# =============================================================================
# FRONTEND FILES UPLOAD (conditional)
# =============================================================================
locals {
  website_buckets = [for k, v in var.buckets : k if v.enable_website]
  frontend_bucket_key = length(local.website_buckets) > 0 ? local.website_buckets[0] : null
  should_upload_files = var.frontend_files_path != "" && local.frontend_bucket_key != null
  frontend_files = local.should_upload_files ? setsubtract(fileset(var.frontend_files_path, "**/*"), var.frontend_files_exclude) : []
}

resource "aws_s3_object" "frontend_files" {
  for_each = local.should_upload_files ? local.frontend_files : []

  bucket = aws_s3_bucket.buckets[local.frontend_bucket_key].id
  key    = each.value
  source = "${var.frontend_files_path}/${each.value}"

  etag = filemd5("${var.frontend_files_path}/${each.value}")

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
# VERSIONING CONFIGURATION (conditional)
# =============================================================================
resource "aws_s3_bucket_versioning" "versioning" {
  for_each = { for k, v in var.buckets : k => v if v.enable_versioning }
  
  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# ENCRYPTION CONFIGURATION (conditional)
# =============================================================================
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  for_each = { for k, v in var.buckets : k => v if v.enable_encryption }
  
  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# LIFECYCLE CONFIGURATION (conditional)
# =============================================================================
resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  for_each = { for k, v in var.buckets : k => v if length(v.lifecycle_rules) > 0 }
  
  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    id     = "${each.key}_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Dynamic transitions based on configuration
    dynamic "transition" {
      for_each = each.value.lifecycle_rules
      content {
        days          = transition.value.transition_days
        storage_class = transition.value.storage_class
      }
    }

    # Noncurrent version expiration (conditional)
    dynamic "noncurrent_version_expiration" {
      for_each = each.value.noncurrent_version_expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = each.value.noncurrent_version_expiration_days
      }
    }
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "bucket_names" {
  value = { for k, v in aws_s3_bucket.buckets : k => v.bucket }
  description = "Map of bucket names by key"
}

output "bucket_arns" {
  value = { for k, v in aws_s3_bucket.buckets : k => v.arn }
  description = "Map of bucket ARNs by key"
}

output "website_endpoints" {
  value = { for k, v in aws_s3_bucket_website_configuration.website : k => v.website_endpoint }
  description = "Map of website endpoints for buckets with website hosting enabled"
}

# Legacy outputs for backwards compatibility
output "frontend_bucket_name" {
  value       = try(aws_s3_bucket.buckets["frontend"].bucket, "")
  description = "Frontend bucket name (backwards compatibility)"
}

output "raw_images_bucket_name" {
  value       = try(aws_s3_bucket.buckets["raw-images"].bucket, "")
  description = "Raw images bucket name (backwards compatibility)"
}

output "raw_images_bucket_arn" {
  value       = try(aws_s3_bucket.buckets["raw-images"].arn, "")
  description = "Raw images bucket ARN (backwards compatibility)"
}

output "processed_images_bucket_name" {
  value       = try(aws_s3_bucket.buckets["processed-images"].bucket, "")
  description = "Processed images bucket name (backwards compatibility)"
}

output "processed_images_bucket_arn" {
  value       = try(aws_s3_bucket.buckets["processed-images"].arn, "")
  description = "Processed images bucket ARN (backwards compatibility)"
}

output "frontend_bucket_website_endpoint" {
  value       = try(aws_s3_bucket_website_configuration.website["frontend"].website_endpoint, "")
  description = "Frontend website endpoint (backwards compatibility)"
}
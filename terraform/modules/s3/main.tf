# =============================================================================
# RANDOM STRING FOR BUCKET NAMING
# =============================================================================

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# S3 BUCKETS - Dynamic creation with for_each pattern
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

  bucket = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = !each.value.public_read
  block_public_policy     = !each.value.public_read
  restrict_public_buckets = !each.value.public_read
  ignore_public_acls      = !each.value.public_read
}

# =============================================================================
# WEBSITE CONFIGURATION
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
# PUBLIC READ POLICY 
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
# FRONTEND FILES UPLOAD 
# =============================================================================
locals {
  website_buckets     = [for k, v in var.buckets : k if v.enable_website]
  frontend_bucket_key = length(local.website_buckets) > 0 ? local.website_buckets[0] : null
  should_upload_files = var.frontend_files_path != "" && local.frontend_bucket_key != null
  frontend_files      = local.should_upload_files ? setsubtract(fileset(var.frontend_files_path, "**/*"), var.frontend_files_exclude) : []
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
# VERSIONING CONFIGURATION
# =============================================================================
resource "aws_s3_bucket_versioning" "versioning" {
  for_each = { for k, v in var.buckets : k => v if v.enable_versioning }

  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# ENCRYPTION CONFIGURATION 
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
# LIFECYCLE CONFIGURATION 
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

    dynamic "transition" {
      for_each = each.value.lifecycle_rules
      content {
        days          = transition.value.transition_days
        storage_class = transition.value.storage_class
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = each.value.noncurrent_version_expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = each.value.noncurrent_version_expiration_days
      }
    }
  }
}


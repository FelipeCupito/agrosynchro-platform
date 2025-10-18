# =============================================================================
# S3 BUCKETS OUTPUTS
# =============================================================================

# Raw Images Bucket Outputs
output "raw_images_bucket_id" {
  description = "Raw images S3 bucket ID"
  value       = aws_s3_bucket.raw_images.id
}

output "raw_images_bucket_arn" {
  description = "Raw images S3 bucket ARN"
  value       = aws_s3_bucket.raw_images.arn
}

output "raw_images_bucket_name" {
  description = "Raw images S3 bucket name"
  value       = aws_s3_bucket.raw_images.bucket
}

output "raw_images_bucket_domain_name" {
  description = "Raw images S3 bucket domain name"
  value       = aws_s3_bucket.raw_images.bucket_domain_name
}

# Processed Images Bucket Outputs
output "processed_images_bucket_id" {
  description = "Processed images S3 bucket ID"
  value       = aws_s3_bucket.processed_images.id
}

output "processed_images_bucket_arn" {
  description = "Processed images S3 bucket ARN"
  value       = aws_s3_bucket.processed_images.arn
}

output "processed_images_bucket_name" {
  description = "Processed images S3 bucket name"
  value       = aws_s3_bucket.processed_images.bucket
}

output "processed_images_bucket_domain_name" {
  description = "Processed images S3 bucket domain name"
  value       = aws_s3_bucket.processed_images.bucket_domain_name
}

# IAM Roles Outputs
output "lambda_s3_role_arn" {
  description = "IAM role ARN for Lambda to access S3"
  value       = aws_iam_role.lambda_s3_role.arn
}

output "fargate_s3_role_arn" {
  description = "IAM role ARN for Fargate to access S3"
  value       = aws_iam_role.fargate_s3_role.arn
}

# Bucket URLs for easy access
output "raw_images_bucket_url" {
  description = "Raw images S3 bucket URL"
  value       = "s3://${aws_s3_bucket.raw_images.bucket}"
}

output "processed_images_bucket_url" {
  description = "Processed images S3 bucket URL"
  value       = "s3://${aws_s3_bucket.processed_images.bucket}"
}
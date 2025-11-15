# =============================================================================
# S3 MODULE OUTPUTS
# =============================================================================
output "bucket_names" {
  value       = { for k, v in aws_s3_bucket.buckets : k => v.bucket }
  description = "Map of bucket names by key"
}

output "bucket_arns" {
  value       = { for k, v in aws_s3_bucket.buckets : k => v.arn }
  description = "Map of bucket ARNs by key"
}

output "website_endpoints" {
  value       = { for k, v in aws_s3_bucket_website_configuration.website : k => v.website_endpoint }
  description = "Map of website endpoints for buckets with website hosting enabled"
}

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
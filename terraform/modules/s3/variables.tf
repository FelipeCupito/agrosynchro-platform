variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "agrosynchro"
}

variable "environment" {
  description = "Environment name (local, dev, prod)"
  type        = string
  default     = "dev"
}

variable "raw_images_lifecycle_days" {
  description = "Number of days to keep raw images before deletion"
  type        = number
  default     = 30
}

variable "processed_images_retention_days" {
  description = "Number of days to keep processed images before deletion"
  type        = number
  default     = 365
}

variable "enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}
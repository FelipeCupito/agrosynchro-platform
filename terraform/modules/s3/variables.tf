variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (local, dev, prod)"
  type        = string
  default     = "dev"
}

# === BUCKET CONFIGURATION ===
variable "buckets" {
  description = "Map of bucket configurations to create"
  type = map(object({
    purpose           = string # Purpose tag for the bucket
    public_read       = bool   # Whether to allow public read access
    enable_website    = bool   # Whether to enable static website hosting
    enable_versioning = bool   # Whether to enable versioning
    enable_encryption = bool   # Whether to enable server-side encryption
    lifecycle_rules = list(object({
      transition_days = number
      storage_class   = string
    }))
    noncurrent_version_expiration_days = number # Days to keep noncurrent versions (0 = no expiration)
  }))
  default = {}
}

# === WEBSITE CONFIGURATION ===
variable "website_index_document" {
  description = "Index document for website hosting"
  type        = string
  default     = "index.html"
}

variable "website_error_document" {
  description = "Error document for website hosting"
  type        = string
  default     = "index.html"
}

# === FILE UPLOAD CONFIGURATION ===
variable "frontend_files_path" {
  description = "Path to frontend build files (empty to skip file upload)"
  type        = string
  default     = ""
}

variable "frontend_files_exclude" {
  description = "List of files to exclude from frontend upload"
  type        = list(string)
  default     = ["env.js"]
}

# === TAGGING ===
variable "additional_tags" {
  description = "Additional tags to apply to all S3 resources"
  type        = map(string)
  default     = {}
}
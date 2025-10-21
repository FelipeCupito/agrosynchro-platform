variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "domain_prefix" {
  description = "Prefix for Cognito domain (must be globally unique)"
  type        = string
}

variable "callback_urls" {
  description = "List of callback URLs for OAuth"
  type        = list(string)
  default     = ["http://localhost:3000/callback"]
}

variable "logout_urls" {
  description = "List of logout URLs for OAuth"
  type        = list(string)
  default     = ["http://localhost:3000/"]
}

variable "oauth_flows" {
  description = "OAuth flows to enable"
  type        = list(string)
  default     = ["code", "implicit"]
}

variable "oauth_scopes" {
  description = "OAuth scopes to enable"
  type        = list(string)
  default     = ["email", "openid", "profile"]
}

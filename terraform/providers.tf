# =============================================================================
# TERRAFORM PROVIDERS CONFIGURATION
# =============================================================================
# AWS production deployment configuration
# =============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# =============================================================================
# AWS PROVIDER CONFIGURATION
# =============================================================================
provider "aws" {
  region = var.aws_region
  access_key = "ASIARAD3BZFKEHOQNNBN"
  secret_key = "BFBz1xKsXjklx7EWhUlurlAYW/EVWWPAjTiVgGfm"
  token      = "IQoJb3JpZ2luX2VjEGoaCXVzLXdlc3QtMiJHMEUCIQDAxfhuwtfzCJOAffBCXk5ms14fE4e6lWT6tZIdXjeQOgIgfS6UKGct2Ox5jxxaR1ujoPdbZeXeRyOeotJdDWHq8GEqrwIIIxAAGgwwNjg5Nzc1NDM1MDgiDCUxlWKO5l89rt+NhiqMAhAjI6/FVRnMoTs5oQ6BIqUPYGgrqE0h7/cuZzhYxdf87oBhKZDBeiadIOOY7WmgMYarKBTG8nf9rrF5Ykv5187cQx872n3QNcV6t3XtGUIlAzeXfDsv4CJ7C86YCpm9UXxYQiL6maNbvC13Q0zapnDLqaCuB4wxnHhCgJyOIy3CGLTqgyTC9QbO7sWPaerU89OFw5OQj4NW27TuvteNddRU4YizDuFu2F94fNXEuHqlDUFX31bfVfpCgSO8KtJcMJahPGzKmwFoZ1jlrisNz/4DYF3QhllhS3ZLxdGUTHhxd8nnaZiJIrTuZkfJTMhm118C3Hm5z61wiVUyqlTNvqlfOxU0iqFFJzf+X0AwmvbgxwY6nQHTqOdS3HTWHaV+2inFZ7OsPKyKReQJ5MLYJfASTHaWG0PEGdCqUZOaT/lKhidEMdOj8XQrC4p8k4cr00Sg4ZtLKVjhdKvNaSr48IgS8Uj23PAGtWlbftzasCceD5hBSD2onXDNJjrNLLxZkMD8DnPNrK6YpwVwS1LaWystChrcVrBmAKVLv4eHyF1d4xaaTW0p0K06W72Z410FF+yf"

  default_tags {
    tags = {
      Project   = "agrosynchro"
      ManagedBy = "terraform"
    }
  }
}
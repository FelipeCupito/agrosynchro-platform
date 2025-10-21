# =============================================================================
# COGNITO USER POOL
# =============================================================================

resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-user-pool"

  # Configuración de atributos
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Esquema de atributos
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Políticas de contraseña
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Configuración de verificación de email
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Código de verificación de ${var.project_name}"
    email_message        = "Tu código de verificación es {####}"
  }

  # Configuración de recuperación de cuenta
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

# =============================================================================
# COGNITO USER POOL CLIENT
# =============================================================================

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  # OAuth 2.0 settings
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = var.oauth_flows
  allowed_oauth_scopes                 = var.oauth_scopes

  # Callback URLs (ajustar según tu frontend)
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Configuración de tokens
  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 30

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  # Deshabilitar secret para aplicaciones públicas (SPAs, móviles)
  generate_secret = false

  # Habilitar lectura de atributos
  read_attributes = ["email", "email_verified"]

  # Prevenir destrucción del cliente
  prevent_user_existence_errors = "ENABLED"
}

# =============================================================================
# COGNITO DOMAIN
# =============================================================================

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project_name}-${var.domain_prefix}"
  user_pool_id = aws_cognito_user_pool.this.id
}

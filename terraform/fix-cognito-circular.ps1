#requires -Version 5.1
param(
    [switch]$AutoApprove,
    [switch]$SkipInit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERR]  $msg" -ForegroundColor Red }

try {
    Write-Info "Resolviendo dependencia circular de Cognito con apply en 2 fases"

    # Ubicar carpeta terraform relativa a este script
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $TerraformDir = $ScriptDir
    if (-not (Test-Path (Join-Path $TerraformDir 'main.tf'))) {
        throw "No se encontró main.tf en: $TerraformDir"
    }

    Push-Location $TerraformDir

    # Verificar herramientas
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw "Terraform no está instalado o no está en PATH"
    }
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI no está instalado o no está en PATH"
    }

    # Init (opcional)
    if (-not $SkipInit) {
        Write-Info "Inicializando Terraform (terraform init)"
        terraform init | Write-Host
        Write-Success "Init completado"
    } else {
        Write-Warn "Saltando terraform init por --SkipInit"
    }

    # Fase 1: apply con campos de Cognito en Lambda vacíos (ya están así en main.tf)
    $applyArgs = @('apply')
    if ($AutoApprove) { $applyArgs += '-auto-approve' }
    Write-Info "Fase 1: terraform $($applyArgs -join ' ')"
    terraform @applyArgs | Write-Host
    Write-Success "Fase 1 completada"

    # Obtener outputs necesarios
    Write-Info "Leyendo outputs de Terraform"
    $cognitoDomain = (terraform output -raw cognito_domain) 2>$null
    $clientId = (terraform output -raw cognito_client_id) 2>$null
    $frontendUrl = (terraform output -raw frontend_website_url) 2>$null
    $region = (terraform output -raw region) 2>$null

    if ([string]::IsNullOrWhiteSpace($region)) { $region = 'us-east-1' }

    if ([string]::IsNullOrWhiteSpace($cognitoDomain) -or [string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($frontendUrl)) {
        Write-Err "No se pudieron obtener outputs requeridos. Valores leídos:" 
        Write-Host "  COGNITO_DOMAIN: '$cognitoDomain'"
        Write-Host "  CLIENT_ID     : '$clientId'"
        Write-Host "  FRONTEND_URL  : '$frontendUrl'"
        throw "Outputs incompletos. Verifica que el apply haya creado Cognito y API Gateway."
    }

    Write-Success "Outputs OK"
    Write-Host "  COGNITO_DOMAIN: $cognitoDomain"
    Write-Host "  CLIENT_ID     : $clientId"
    Write-Host "  FRONTEND_URL  : $frontendUrl"
    Write-Host "  REGION        : $region"

    # Fase 2: Actualizar variables de entorno de la Lambda de callback con valores reales
    Write-Info "Fase 2: Actualizando Lambda 'agrosynchro-cognito-callback' con variables reales"

    $envVarsArg = "Variables={COGNITO_DOMAIN=$cognitoDomain,CLIENT_ID=$clientId,FRONTEND_URL=$frontendUrl}"
    aws lambda update-function-configuration `
        --function-name agrosynchro-cognito-callback `
        --environment "$envVarsArg" `
        --region $region | Out-Null

    Write-Success "Lambda actualizada correctamente"

    Write-Info "Proceso finalizado"
    Write-Host "Resumen:" -ForegroundColor Magenta
    Write-Host "  1) terraform apply ejecutado (Fase 1)"
    Write-Host "  2) Lambda de callback actualizada con COGNITO_DOMAIN/CLIENT_ID/FRONTEND_URL (Fase 2)"
    Write-Host "\nPuedes probar el flujo OAuth en: $frontendUrl" -ForegroundColor Magenta
}
catch {
    Write-Err $_
    exit 1
}
finally {
    Pop-Location -ErrorAction SilentlyContinue | Out-Null
}

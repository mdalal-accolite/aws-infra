<#
.SYNOPSIS
  Fills in the Secrets Manager values that Terraform deliberately leaves as placeholders.

.DESCRIPTION
  PowerShell twin of seed-secrets.sh. Run ONCE per environment, from your laptop, after
  40-data and 36-secrets have been applied.

  Terraform has `ignore_changes = [secret_string]` on these, so it will never overwrite
  what this script writes.

.EXAMPLE
  .\seed-secrets.ps1 stage

.NOTES
  If PowerShell refuses to run this:
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("stage", "prod")]
  [string]$Environment
)

$ErrorActionPreference = "Stop"

$root   = Split-Path -Parent $PSScriptRoot
$prefix = "scribl/$Environment"

function New-RandomHex {
  param([int]$Bytes = 32)
  $buffer = New-Object byte[] $Bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
  return ($buffer | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Set-Secret {
  param([string]$Id, [string]$Value)
  Write-Host "    $Id"
  aws secretsmanager put-secret-value --secret-id $Id --secret-string $Value | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed writing $Id" }
}

Write-Host "==> Reading endpoints from Terraform state" -ForegroundColor Cyan
Push-Location (Join-Path $root "stacks\40-data")
try {
  $dbSecretArn = terraform output -raw db_master_secret_arn
  $dbProxy     = terraform output -raw db_proxy_endpoint
  $dbDirect    = terraform output -raw db_endpoint
  if ($LASTEXITCODE -ne 0) { throw "terraform output failed - has 40-data been applied?" }
}
finally { Pop-Location }

Write-Host "==> Reading the RDS-managed master password" -ForegroundColor Cyan
$creds = aws secretsmanager get-secret-value --secret-id $dbSecretArn `
           --query SecretString --output text | ConvertFrom-Json
$dbUser = $creds.username
$dbPass = $creds.password

# The password is URL-encoded in case RDS generated one containing reserved characters.
Add-Type -AssemblyName System.Web
$dbPassEnc = [System.Web.HttpUtility]::UrlEncode($dbPass)

$proxyUrl  = "postgresql://${dbUser}:${dbPassEnc}@${dbProxy}:5432/scribl?sslmode=require"
$directUrl = "postgresql://${dbUser}:${dbPassEnc}@${dbDirect}:5432/scribl?sslmode=require"

Write-Host "==> Writing secrets under $prefix/" -ForegroundColor Cyan

$apiSecret = @{
  DATABASE_URL        = $proxyUrl
  INTERNAL_JOB_SECRET = New-RandomHex 32
} | ConvertTo-Json -Compress

Set-Secret "$prefix/api"                             $apiSecret
Set-Secret "$prefix/db/database-url"                 $proxyUrl
Set-Secret "$prefix/migrate/database-url"            $directUrl
Set-Secret "$prefix/admin-api/session-cookie-secret" (New-RandomHex 32)
Set-Secret "$prefix/admin-api/origin-verify"         (New-RandomHex 32)

Write-Host ""
Write-Host "Left alone on purpose:" -ForegroundColor Yellow
Write-Host "  $prefix/admin-api/idp-client-secret  - Terraform wrote the Cognito client id/secret"
Write-Host "  $prefix/db-proxy/credentials         - used by the RDS Proxy itself"
Write-Host "  $prefix/redis/auth-token             - Terraform generated this"
Write-Host "  $prefix/ses/smtp-credentials         - written by the 38-email component"
Write-Host ""
Write-Host "Done. Verify with:" -ForegroundColor Green
Write-Host "  aws secretsmanager list-secrets --filters Key=name,Values=$prefix --query 'SecretList[].Name' --output table"

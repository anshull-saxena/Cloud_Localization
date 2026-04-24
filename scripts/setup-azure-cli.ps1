param(
    [string]$ResourceGroup,
    [string]$StorageAccount,
    [switch]$WriteConfig
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $projectRoot "config.json"

if (-not $env:AZURE_CONFIG_DIR) {
    $env:AZURE_CONFIG_DIR = Join-Path $projectRoot ".azure"
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is not installed. Install it first, then rerun this script."
}

New-Item -ItemType Directory -Force -Path $env:AZURE_CONFIG_DIR | Out-Null

Write-Host "Azure CLI config dir: $($env:AZURE_CONFIG_DIR)"
Write-Host "Project config file: $configPath"
Write-Host ""

az version | Out-Null
Write-Host "Azure CLI is available."

if (-not (az account show 2>$null)) {
    Write-Host "No active Azure login found for this project config." -ForegroundColor Yellow
    Write-Host "Run the following command, then rerun this script:" -ForegroundColor Yellow
    Write-Host "  `$env:AZURE_CONFIG_DIR=`"$($env:AZURE_CONFIG_DIR)`"; az login --use-device-code" -ForegroundColor White
    exit 0
}

Write-Host "Azure login detected:"
az account show --query "{subscription:name, user:user.name, tenant:tenantId}" -o table

if (-not $StorageAccount -and (Test-Path $configPath)) {
    $config = Get-Content $configPath | ConvertFrom-Json
    $StorageAccount = $config.StorageAccountName
}

if (-not $ResourceGroup -or -not $StorageAccount) {
    Write-Host ""
    Write-Host "Azure CLI is ready for base_version."
    Write-Host "Pass -ResourceGroup and -StorageAccount to resolve the storage connection string."
    if ($StorageAccount) {
        Write-Host "Detected storage account from config.json: $StorageAccount"
    }
    exit 0
}

Write-Host ""
Write-Host "Resolving storage connection string for $StorageAccount in $ResourceGroup..."
$connectionString = az storage account show-connection-string `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --query connectionString `
    -o tsv

if (-not $connectionString) {
    throw "Azure CLI did not return a connection string."
}

Write-Host "Connection string resolved successfully."

if ($WriteConfig) {
    $config = Get-Content $configPath | ConvertFrom-Json
    $config.ConnectionString = $connectionString
    $config.StorageAccountName = $StorageAccount
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-Host "Updated config.json with the resolved connection string."
} else {
    Write-Host "Run again with -WriteConfig to store it in config.json."
}


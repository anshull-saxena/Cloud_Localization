# Verify Azure Resources Script
# This script helps verify if your Azure resources exist

Write-Host "=== Azure Resource Verification ===" -ForegroundColor Cyan
Write-Host ""

# Load config
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (!(Test-Path $configPath)) {
    Write-Error "Config file not found at $configPath"
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json

Write-Host "Checking configuration..." -ForegroundColor Yellow
Write-Host "Storage Account: $($config.StorageAccountName)"
Write-Host "Container Name: $($config.TempContainerName)"
Write-Host ""

# Test DNS resolution
Write-Host "Testing DNS resolution..." -ForegroundColor Yellow
$storageEndpoint = "$($config.StorageAccountName).blob.core.windows.net"
try {
    $resolved = [System.Net.Dns]::GetHostAddresses($storageEndpoint)
    Write-Host "✓ DNS Resolution successful: $storageEndpoint" -ForegroundColor Green
    Write-Host "  IP Address: $($resolved[0].IPAddressToString)" -ForegroundColor Gray
} catch {
    Write-Host "✗ DNS Resolution FAILED: $storageEndpoint" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "SOLUTION:" -ForegroundColor Yellow
    Write-Host "  The storage account '$($config.StorageAccountName)' doesn't exist or is inaccessible." -ForegroundColor Yellow
    Write-Host "  Please either:" -ForegroundColor Yellow
    Write-Host "    1. Create this storage account in Azure Portal" -ForegroundColor Yellow
    Write-Host "    2. Or update config.json with an existing storage account name" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Test connection string parsing
Write-Host "Testing connection string..." -ForegroundColor Yellow
if ($config.ConnectionString -match "AccountName=([^;]+)") {
    $connStrAcctName = $matches[1]
    if ($connStrAcctName -eq $config.StorageAccountName) {
        Write-Host "✓ Connection string account name matches config" -ForegroundColor Green
    } else {
        Write-Host "✗ WARNING: Connection string uses '$connStrAcctName' but config has '$($config.StorageAccountName)'" -ForegroundColor Yellow
    }
} else {
    Write-Host "✗ Unable to parse connection string" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "If the storage account doesn't exist, create it with:" -ForegroundColor Gray
Write-Host "  az storage account create --name YOUR_UNIQUE_NAME --resource-group YOUR_RG --location eastus --sku Standard_LRS" -ForegroundColor White
Write-Host ""
Write-Host "Then update config.json with the new account name and connection string" -ForegroundColor Gray

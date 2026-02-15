#!/usr/bin/env pwsh
# ============================================
# Quick SQL Setup - Create Database & Schema
# ============================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick SQL Database Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for password
$password = Read-Host "Enter SQL admin password" -AsPlainText
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Error "Password is required"
    exit 1
}

Write-Host ""
Write-Host "This will create:" -ForegroundColor Yellow
Write-Host "  • SQL Server: cloudlocalization-sql.database.windows.net" -ForegroundColor White
Write-Host "  • Database: TranslationMemory" -ForegroundColor White
Write-Host "  • Region: Central India" -ForegroundColor White
Write-Host "  • Cost: ~$5-10/month (Basic tier)" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Setup cancelled" -ForegroundColor Yellow
    exit 0
}

# Run the full setup
& "$PSScriptRoot/setup-azure-sql.ps1" -AdminPassword $password

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ All Done!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Copy the connection string above" -ForegroundColor White
Write-Host "2. Go to Azure DevOps → Your Pipeline → Edit → Variables" -ForegroundColor White
Write-Host "3. Update AZURE_SQL_CONN variable" -ForegroundColor White
Write-Host "4. Mark it as Secret ⚠" -ForegroundColor White
Write-Host "5. Save and run your pipeline!" -ForegroundColor White

#!/usr/bin/env pwsh
# ============================================
# Azure SQL Database Setup Script
# ============================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "CloudLocalization-RG",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "centralindia",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlServer = "cloudlocalization-sql",
    
    [Parameter(Mandatory=$false)]
    [string]$Database = "TranslationMemory",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminUser = "sqladmin",
    
    [Parameter(Mandatory=$true)]
    [string]$AdminPassword
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure SQL Database Setup for Translation Memory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if user is logged in to Azure
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    Write-Host "Not logged in to Azure. Please login..." -ForegroundColor Yellow
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to Azure"
        exit 1
    }
} else {
    Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host "✓ Subscription: $($account.name)" -ForegroundColor Green
}
Write-Host ""

# Create or verify resource group
Write-Host "Creating resource group '$ResourceGroup'..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Resource group ready" -ForegroundColor Green
} else {
    Write-Error "Failed to create resource group"
    exit 1
}
Write-Host ""

# Create SQL Server
Write-Host "Creating SQL Server '$SqlServer'..." -ForegroundColor Yellow
$serverResult = az sql server create `
    --name $SqlServer `
    --resource-group $ResourceGroup `
    --location $Location `
    --admin-user $AdminUser `
    --admin-password $AdminPassword `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ SQL Server created successfully" -ForegroundColor Green
    $server = $serverResult | ConvertFrom-Json
    Write-Host "  Server FQDN: $($server.fullyQualifiedDomainName)" -ForegroundColor Cyan
} else {
    if ($serverResult -like "*exists*") {
        Write-Host "✓ SQL Server already exists" -ForegroundColor Yellow
    } else {
        Write-Error "Failed to create SQL Server: $serverResult"
        exit 1
    }
}
Write-Host ""

# Create firewall rule for Azure Services
Write-Host "Configuring firewall to allow Azure services..." -ForegroundColor Yellow
az sql server firewall-rule create `
    --resource-group $ResourceGroup `
    --server $SqlServer `
    --name "AllowAzureServices" `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0 `
    --output none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Firewall rule configured" -ForegroundColor Green
} else {
    Write-Host "⚠ Firewall rule may already exist (this is okay)" -ForegroundColor Yellow
}
Write-Host ""

# Create database
Write-Host "Creating database '$Database'..." -ForegroundColor Yellow
$dbResult = az sql db create `
    --resource-group $ResourceGroup `
    --server $SqlServer `
    --name $Database `
    --service-objective Basic `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Database created successfully" -ForegroundColor Green
    $db = $dbResult | ConvertFrom-Json
    Write-Host "  Tier: $($db.sku.tier)" -ForegroundColor Cyan
    Write-Host "  Capacity: $($db.sku.capacity) DTU" -ForegroundColor Cyan
} else {
    if ($dbResult -like "*exists*") {
        Write-Host "✓ Database already exists" -ForegroundColor Yellow
    } else {
        Write-Error "Failed to create database: $dbResult"
        exit 1
    }
}
Write-Host ""

# Generate connection string
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

$connectionString = "Server=tcp:$SqlServer.database.windows.net,1433;Initial Catalog=$Database;Persist Security Info=False;User ID=$AdminUser;Password=$AdminPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

Write-Host "Connection String:" -ForegroundColor Cyan
Write-Host $connectionString -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Run the SQL schema script: setup-azure-sql.sql" -ForegroundColor White
Write-Host "2. Update Azure DevOps pipeline variable AZURE_SQL_CONN with the connection string above" -ForegroundColor White
Write-Host "3. Mark the variable as Secret in Azure DevOps" -ForegroundColor White
Write-Host ""

# Test connection
Write-Host "Testing database connection..." -ForegroundColor Yellow
try {
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()
    Write-Host "✓ Connection test successful!" -ForegroundColor Green
    
    $command = $connection.CreateCommand()
    $command.CommandText = "SELECT @@VERSION"
    $version = $command.ExecuteScalar()
    Write-Host "✓ SQL Server Version: $($version.Split("`n")[0])" -ForegroundColor Green
    
    $connection.Close()
} catch {
    Write-Warning "Connection test failed: $_"
    Write-Host "You may need to add your IP address to the firewall rules" -ForegroundColor Yellow
}

# Create database schema
Write-Host ""
Write-Host "Creating database schema (tables)..." -ForegroundColor Yellow

$schemaSQL = @"
-- Create SourceText table
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'SourceText')
BEGIN
    CREATE TABLE SourceText (
        SourceID INT IDENTITY(1,1) PRIMARY KEY,
        SourceText NVARCHAR(MAX) NOT NULL,
        TargetCultureID NVARCHAR(10) NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETDATE()
    );
    CREATE INDEX IX_SourceText_Culture ON SourceText(TargetCultureID);
    PRINT 'Created SourceText table';
END
ELSE
BEGIN
    PRINT 'SourceText table already exists';
END

-- Create TargetText table
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'TargetText')
BEGIN
    CREATE TABLE TargetText (
        TargetID INT IDENTITY(1,1) PRIMARY KEY,
        SourceID INT NOT NULL,
        TranslatedText NVARCHAR(MAX) NOT NULL,
        UpdatedAt DATETIME2 NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_TargetText_SourceText FOREIGN KEY (SourceID) REFERENCES SourceText(SourceID) ON DELETE CASCADE
    );
    CREATE INDEX IX_TargetText_SourceID ON TargetText(SourceID);
    PRINT 'Created TargetText table';
END
ELSE
BEGIN
    PRINT 'TargetText table already exists';
END

SELECT TABLE_NAME, (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = t.TABLE_NAME) AS ColumnCount
FROM INFORMATION_SCHEMA.TABLES t
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
"@

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()
    
    $command = $connection.CreateCommand()
    $command.CommandText = $schemaSQL
    $command.CommandTimeout = 60
    
    $reader = $command.ExecuteReader()
    
    # Read all result sets
    do {
        while ($reader.Read()) {
            $tableName = $reader["TABLE_NAME"]
            $columnCount = $reader["ColumnCount"]
            Write-Host "  ✓ Table: $tableName ($columnCount columns)" -ForegroundColor Cyan
        }
    } while ($reader.NextResult())
    
    $reader.Close()
    $connection.Close()
    
    Write-Host "✓ Database schema created successfully!" -ForegroundColor Green
    
} catch {
    Write-Warning "Failed to create schema: $_"
    Write-Host "You can create the schema manually using Azure Portal Query Editor" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓✓✓ SETUP COMPLETE! ✓✓✓" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to Azure DevOps Pipeline Variables:" -ForegroundColor Cyan
Write-Host "Variable Name: AZURE_SQL_CONN" -ForegroundColor White
Write-Host "Value: (copy from above)" -ForegroundColor White
Write-Host "Type: Secret ✓" -ForegroundColor White
Write-Host ""
Write-Host "Estimated monthly cost: ~$5-10 USD (Basic tier)" -ForegroundColor Cyan

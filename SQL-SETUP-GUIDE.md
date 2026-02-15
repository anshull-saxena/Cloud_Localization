# SQL Database Setup - Three Easy Methods

## 🚀 Method 1: Quick PowerShell Script (Recommended)

Just run one command - it creates everything automatically:

```bash
./quick-setup-sql.ps1
```

This will:
- ✅ Create SQL Server + Database
- ✅ Create database schema (tables)
- ✅ Test connection
- ✅ Output connection string

---

## 🌐 Method 2: Azure Portal (No scripts needed)

### Step 1: Create Database

1. Go to [Azure Portal](https://portal.azure.com)
2. Click **"Create a resource"** → **"SQL Database"**
3. Fill in:
   - **Database name**: `TranslationMemory`
   - **Server**: Create new
     - Name: `cloudlocalization-sql`
     - Location: `Central India`
     - Authentication: `SQL authentication`
     - Admin login: `sqladmin`
     - Password: `YourStrongPassword123!` (pick your own)
   - **Compute + storage**: Basic (5 DTU, 2GB)
   - **Networking**: 
     - Allow Azure services: **YES** ✓
4. Click **Review + Create** → **Create**

### Step 2: Create Tables using Query Editor

1. In Azure Portal, go to your database → **Query editor**
2. Login with your SQL credentials
3. Copy-paste this SQL and click **Run**:

```sql
-- Create SourceText table
CREATE TABLE SourceText (
    SourceID INT IDENTITY(1,1) PRIMARY KEY,
    SourceText NVARCHAR(MAX) NOT NULL,
    TargetCultureID NVARCHAR(10) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETDATE()
);

CREATE INDEX IX_SourceText_Culture ON SourceText(TargetCultureID);

-- Create TargetText table
CREATE TABLE TargetText (
    TargetID INT IDENTITY(1,1) PRIMARY KEY,
    SourceID INT NOT NULL,
    TranslatedText NVARCHAR(MAX) NOT NULL,
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_TargetText_SourceText FOREIGN KEY (SourceID) 
        REFERENCES SourceText(SourceID) ON DELETE CASCADE
);

CREATE INDEX IX_TargetText_SourceID ON TargetText(SourceID);

-- Verify
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES;
```

4. You should see: `SourceText` and `TargetText` in the results ✓

### Step 3: Get Connection String

1. Go to your database → **Settings** → **Connection strings**
2. Copy the **ADO.NET** connection string
3. Replace `{your_password}` with your actual password

---

## 🔧 Method 3: Azure CLI (Command Line)

```bash
# Login
az login

# Create everything
az sql server create \
  --name cloudlocalization-sql \
  --resource-group CloudLocalization-RG \
  --location centralindia \
  --admin-user sqladmin \
  --admin-password "YourPassword123!"

# Allow Azure services
az sql server firewall-rule create \
  --resource-group CloudLocalization-RG \
  --server cloudlocalization-sql \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Create database
az sql db create \
  --resource-group CloudLocalization-RG \
  --server cloudlocalization-sql \
  --name TranslationMemory \
  --service-objective Basic
```

Then create tables using **Method 2 Step 2** above (Query Editor).

---

## 📝 Final Step: Update Pipeline Variable

**For ALL methods:**

1. Go to **Azure DevOps** → Your Pipeline → **Edit** → **Variables**
2. Find or create variable: `AZURE_SQL_CONN`
3. Paste your connection string (format below)
4. **Mark as Secret** ✓
5. **Save**

**Connection String Format:**
```
Server=tcp:cloudlocalization-sql.database.windows.net,1433;Initial Catalog=TranslationMemory;Persist Security Info=False;User ID=sqladmin;Password=YourPassword123!;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

---

## ✅ Verification

Your pipeline output should show:
```
✓ Translation memory (SQL) is available and connected.
```

Instead of:
```
Translation memory (SQL) is not configured. Proceeding without caching.
```

---

## 💰 Cost

- **Basic tier**: ~$5-10 USD/month
- **Good for**: Development + moderate production workloads
- **Auto-scaling**: Can upgrade later if needed

---

## ❓ Troubleshooting

**Error: "Keyword not supported: 'authentication'"**
- ✅ Fixed! Connection string format is correct now

**Can't connect from pipeline:**
- Make sure firewall allows Azure services (0.0.0.0 rule)

**Tables don't exist:**
- Run the CREATE TABLE commands in Query Editor

**Want to delete and start over:**
```bash
az sql db delete --name TranslationMemory --resource-group CloudLocalization-RG --server cloudlocalization-sql
```

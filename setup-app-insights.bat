@echo off
REM Quick setup script for Application Insights (Windows)
REM Run this to install dependencies and test connection

echo ======================================================================
echo Application Insights Setup for Localization Pipeline
echo ======================================================================
echo.

REM Check Python version
echo [Python] Checking Python version...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Please install Python 3.7+
    exit /b 1
)
python --version
echo [OK] Python is installed
echo.

REM Install dependencies
echo [Install] Installing required dependencies...
pip install -r requirements.txt
if errorlevel 1 (
    echo [ERROR] Failed to install dependencies
    exit /b 1
)
echo [OK] Dependencies installed
echo.

REM Check if config has real connection string
echo [Config] Checking configuration...
findstr /C:"__APP_INSIGHTS_CONN__" API_based_HFace_AppInsight\config.json >nul
if not errorlevel 1 (
    echo [WARNING] Application Insights connection string not configured yet
    echo.
    echo Please follow these steps:
    echo.
    echo 1. Create Application Insights in Azure Portal:
    echo    https://portal.azure.com - Create Resource - Application Insights
    echo.
    echo 2. Copy the Connection String from the Overview page
    echo.
    echo 3. Edit: API_based_HFace_AppInsight\config.json
    echo    Replace: "__APP_INSIGHTS_CONN__"
    echo    With your connection string (should start with 'InstrumentationKey='^)
    echo.
    echo 4. Run: python test-app-insights.py
    echo.
    echo Full setup guide: SETUP-APPLICATION-INSIGHTS.md
    exit /b 0
) else (
    echo [OK] Connection string appears to be configured
    echo.
)

REM Run test
echo [Test] Testing Application Insights connection...
echo.
python test-app-insights.py

echo.
echo ======================================================================
echo Setup Complete!
echo ======================================================================
echo.
echo Next steps:
echo 1. Wait 2-5 minutes for test data to appear
echo 2. Check Azure Portal - Application Insights - Logs
echo 3. Run your translation pipeline
echo 4. Use queries from ApplicationInsights-Queries.md
echo.
pause

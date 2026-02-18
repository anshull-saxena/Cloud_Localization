#!/bin/bash
# Quick setup script for Application Insights
# Run this to install dependencies and test connection

set -e  # Exit on error

echo "======================================================================"
echo "Application Insights Setup for Localization Pipeline"
echo "======================================================================"
echo ""

# Check Python version
echo "🐍 Checking Python version..."
python3 --version || { echo "❌ Python 3 not found. Please install Python 3.7+"; exit 1; }
echo "✅ Python is installed"
echo ""

# Install dependencies
echo "📦 Installing required dependencies..."
pip3 install -r requirements.txt
echo "✅ Dependencies installed"
echo ""

# Check if config has real connection string
echo "🔍 Checking configuration..."
if grep -q "__APP_INSIGHTS_CONN__" API_based_HFace_AppInsight/config.json; then
    echo "⚠️  Application Insights connection string not configured yet"
    echo ""
    echo "📝 Please follow these steps:"
    echo ""
    echo "1. Create Application Insights in Azure Portal:"
    echo "   https://portal.azure.com → Create Resource → Application Insights"
    echo ""
    echo "2. Copy the Connection String from the Overview page"
    echo ""
    echo "3. Edit: API_based_HFace_AppInsight/config.json"
    echo "   Replace: \"__APP_INSIGHTS_CONN__\""
    echo "   With your connection string (should start with 'InstrumentationKey=')"
    echo ""
    echo "4. Run: python3 test-app-insights.py"
    echo ""
    echo "📚 Full setup guide: SETUP-APPLICATION-INSIGHTS.md"
    exit 0
else
    echo "✅ Connection string appears to be configured"
    echo ""
fi

# Run test
echo "🧪 Testing Application Insights connection..."
echo ""
python3 test-app-insights.py

echo ""
echo "======================================================================"
echo "Setup Complete!"
echo "======================================================================"
echo ""
echo "Next steps:"
echo "1. Wait 2-5 minutes for test data to appear"
echo "2. Check Azure Portal → Application Insights → Logs"
echo "3. Run your translation pipeline"
echo "4. Use queries from ApplicationInsights-Queries.md"
echo ""

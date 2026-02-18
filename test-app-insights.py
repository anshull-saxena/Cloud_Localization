#!/usr/bin/env python3
"""
Test script to verify Azure Application Insights connection and send test telemetry
"""

import json
import logging
import time
import sys

try:
    from opencensus.ext.azure.log_exporter import AzureLogHandler
    OPENCENSUS_AVAILABLE = True
except ImportError:
    OPENCENSUS_AVAILABLE = False
    print("❌ ERROR: opencensus-ext-azure not installed")
    print("   Install it with: pip install opencensus-ext-azure")
    sys.exit(1)

def load_config(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)

def test_app_insights(connection_string):
    """Test Application Insights connection by sending test telemetry"""
    
    print(f"🔍 Testing Application Insights connection...")
    print(f"   Connection String: {connection_string[:50]}...")
    
    # Configure logger with App Insights
    logger = logging.getLogger("test_logger")
    logger.setLevel(logging.INFO)
    
    try:
        # Add Azure Log Handler
        handler = AzureLogHandler(connection_string=connection_string)
        logger.addHandler(handler)
        
        print("✅ Application Insights handler initialized successfully")
        
        # Send test messages with different severity levels
        print("\n📤 Sending test telemetry...")
        
        # Test 1: Info message
        logger.info("TEST: Application Insights connection test - INFO level")
        print("   ✓ Sent INFO level log")
        
        # Test 2: Warning message
        logger.warning("TEST: Application Insights connection test - WARNING level")
        print("   ✓ Sent WARNING level log")
        
        # Test 3: Custom dimensions
        test_properties = {
            "TestType": "ConnectionVerification",
            "Timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "Status": "Success",
            "Version": "1.0"
        }
        logger.info("TEST: Application Insights with custom dimensions", 
                   extra={"custom_dimensions": test_properties})
        print("   ✓ Sent log with custom dimensions")
        
        # Test 4: Simulated translation metrics
        mock_metrics = {
            "File": "test_file.resx",
            "Lang": "fr-FR",
            "Segments": 100,
            "TMHits": 45,
            "NMTCalls": 55,
            "AvgLatency": 0.234,
            "TotalTime": 15.7
        }
        logger.info("TranslationMetrics", extra={"custom_dimensions": mock_metrics})
        print("   ✓ Sent simulated translation metrics")
        
        # Flush logs to ensure they're sent
        print("\n⏳ Flushing logs (this may take a few seconds)...")
        handler.flush()
        time.sleep(3)  # Give time for telemetry to be sent
        
        print("\n✅ Test completed successfully!")
        print("\n📊 Next steps:")
        print("   1. Wait 2-5 minutes for data to appear in Azure Portal")
        print("   2. Go to: Azure Portal → Application Insights → Logs")
        print("   3. Run this query:")
        print("\n" + "="*60)
        print("traces")
        print("| where timestamp > ago(10m)")
        print("| where message contains 'TEST'")
        print("| project timestamp, message, customDimensions")
        print("| order by timestamp desc")
        print("="*60)
        
        return True
        
    except Exception as e:
        print(f"\n❌ ERROR: Failed to send telemetry")
        print(f"   Error: {str(e)}")
        print(f"\n   Common issues:")
        print(f"   - Invalid connection string format")
        print(f"   - Missing InstrumentationKey in connection string")
        print(f"   - Network connectivity issues")
        print(f"   - App Insights resource not created in Azure")
        return False

def main():
    print("="*70)
    print("Azure Application Insights Connection Test")
    print("="*70 + "\n")
    
    if not OPENCENSUS_AVAILABLE:
        return
    
    # Load config
    config_path = "API_based_HFace_AppInsight/config.json"
    try:
        config = load_config(config_path)
        conn_str = config.get("app_insights_connection_string", "")
    except Exception as e:
        print(f"❌ ERROR: Could not load config from {config_path}")
        print(f"   {str(e)}")
        return
    
    # Validate connection string
    if not conn_str or conn_str == "__APP_INSIGHTS_CONN__":
        print("❌ ERROR: Application Insights connection string not configured")
        print("\n📝 Setup Instructions:")
        print("\n1. Create Application Insights resource in Azure Portal:")
        print("   - Go to portal.azure.com")
        print("   - Search for 'Application Insights'")
        print("   - Click 'Create'")
        print("   - Fill in required details and create")
        print("\n2. Get the Connection String:")
        print("   - Open your Application Insights resource")
        print("   - Go to 'Overview' or 'Properties'")
        print("   - Copy the 'Connection String' (not just the Instrumentation Key)")
        print("   - It should look like:")
        print("     InstrumentationKey=xxxxx-xxxx-xxxx;IngestionEndpoint=https://...")
        print("\n3. Update config.json:")
        print(f"   - Edit: {config_path}")
        print("   - Replace '__APP_INSIGHTS_CONN__' with your connection string")
        print("\n4. Re-run this test script")
        return
    
    # Test the connection
    success = test_app_insights(conn_str)
    
    if success:
        print("\n✨ You can now run your translation pipeline and view logs in Azure!")
    else:
        print("\n⚠️  Please fix the issues above and try again")

if __name__ == "__main__":
    main()

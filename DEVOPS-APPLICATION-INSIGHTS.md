# Application Insights - Azure DevOps Setup

## ✅ Files Updated

All necessary files have been updated to support Application Insights in Azure DevOps:

1. **`translation.py`** - Reads connection string from environment variable (DevOps) or config
2. **`azure-pipelines.yml`** (root) - Injects `APPINSIGHTS_CONNECTION_STRING` 
3. **`API_based_HFace_AppInsight/azure-pipelines.yml`** - All 3 phases inject the connection string

---

## 🔧 Azure DevOps Pipeline Setup

### Step 1: Add Pipeline Variable

In your Azure DevOps project:

1. Go to **Pipelines** → Select your pipeline → **Edit**
2. Click **Variables** (top right)
3. Click **New variable**
4. Configure:
   - **Name**: `APPINSIGHTS_CONNECTION_STRING`
   - **Value**: Your connection string from Azure Portal
   - ☑️ **Keep this value secret** 
5. Click **OK** → **Save**

### Step 2: Get Connection String from Azure

1. Go to **Azure Portal** → **Application Insights**
2. Open your App Insights resource (or create new one)
3. Click **Overview** → Copy **Connection String**
4. Format: `InstrumentationKey=xxxxx-xxxx;IngestionEndpoint=https://...`

---

## 📋 What's Configured

### Pipeline Stages That Log to App Insights:

✅ **Phase 1 (Extract)** - Config injection includes App Insights  
✅ **Phase 2 (Translate)** - **Main logging happens here** with translation metrics  
✅ **Phase 3 (Integrate)** - Config injection includes App Insights

### Metrics Logged Per Translation Job:

```json
{
  "File": "resx_file_01.fr-FR.xlf",
  "Lang": "fr-FR",
  "Segments": 150,
  "TMHits": 67,
  "NMTCalls": 83,
  "AvgLatency": 0.234,
  "TotalTime": 18.5
}
```

---

## 🚀 How to Use

### 1. Run Your Pipeline

Just trigger your pipeline normally - App Insights is **automatically configured**:

```bash
# Push to main branch to trigger, or manually run from DevOps UI
git push origin main
```

### 2. Wait for Data (2-5 minutes)

After pipeline completes, wait 2-5 minutes for telemetry ingestion.

### 3. Query Logs in Azure Portal

Go to: **Azure Portal** → **Application Insights** → **Logs**

**Quick Query - Recent Translation Jobs:**
```kusto
traces
| where timestamp > ago(1h)
| where message contains "TranslationMetrics"
| extend File = tostring(customDimensions.File)
| extend Lang = tostring(customDimensions.Lang)
| extend Segments = toint(customDimensions.Segments)
| project timestamp, File, Lang, Segments
| order by timestamp desc
```

**Performance by Language:**
```kusto
traces
| where timestamp > ago(24h)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| extend TotalTime = toreal(customDimensions.TotalTime)
| summarize AvgTime = avg(TotalTime), Jobs = count() by Lang
| order by AvgTime desc
```

**Cache Hit Rate:**
```kusto
traces
| where timestamp > ago(24h)
| where message contains "TranslationMetrics"
| extend TMHits = toint(customDimensions.TMHits)
| extend Segments = toint(customDimensions.Segments)
| summarize TotalHits = sum(TMHits), TotalSegments = sum(Segments)
| extend CacheHitRate = round(100.0 * TotalHits / TotalSegments, 2)
| project CacheHitRate, TotalHits, TotalSegments
```

---

## 📊 Azure DevOps Integration Features

### Environment Variable Priority:

```python
# In translation.py - reads in this order:
app_insights_conn = os.getenv("APPINSIGHTS_CONNECTION_STRING")  # 1. DevOps Variable (Priority)
                 or config.get("app_insights_connection_string")  # 2. Config file (Fallback)
```

### Benefits:
- ✅ **Secure**: Connection string not in code/config
- ✅ **Flexible**: Different values per environment (dev/prod)
- ✅ **Easy**: Works out of the box once variable is set

---

## 📈 Viewing Logs in Azure Portal

### Option 1: Logs (KQL Queries)
**Azure Portal** → **Application Insights** → **Logs**
- Most powerful, use KQL queries
- See: `ApplicationInsights-Queries.md` for 50+ queries

### Option 2: Transaction Search
**Azure Portal** → **Application Insights** → **Transaction search**
- Simple UI for browsing logs
- Filter by time, severity, custom dimensions

### Option 3: Dashboards
**Azure Portal** → **Dashboards** → **Create**
- Pin queries for real-time monitoring
- Great for team visibility

---

## 🎯 Common Queries for DevOps

### Pipeline Execution Timeline
```kusto
traces
| where timestamp > ago(24h)
| where message contains "Phase" or message contains "TranslationMetrics"
| project timestamp, message
| order by timestamp asc
| render timechart
```

### Error Detection
```kusto
traces
| where timestamp > ago(24h)
| where severityLevel >= 3  // Warning and above
| project timestamp, severityLevel, message
| order by timestamp desc
```

### Daily Translation Volume
```kusto
traces
| where timestamp > ago(30d)
| where message contains "TranslationMetrics"
| extend Segments = toint(customDimensions.Segments)
| summarize TotalSegments = sum(Segments) by bin(timestamp, 1d)
| render columnchart
```

---

## 🔔 Setting Up Alerts

### Alert 1: High Latency

1. **Azure Portal** → **Application Insights** → **Alerts** → **New alert rule**
2. **Condition**: Custom log search
3. **Query**:
```kusto
traces
| where message contains "TranslationMetrics"
| extend AvgLatency = toreal(customDimensions.AvgLatency)
| where AvgLatency > 5.0
| summarize count()
```
4. **Threshold**: Result count greater than 0
5. **Action**: Email your team

### Alert 2: Pipeline Failures

1. **Condition**: Custom log search
2. **Query**:
```kusto
traces
| where severityLevel >= 3
| summarize ErrorCount = count()
| where ErrorCount > 5
```
3. **Threshold**: When error count exceeds 5 in 15 minutes

---

## 🐛 Troubleshooting

### Issue: No logs appearing after pipeline runs

**Check:**
1. ✅ Pipeline variable `APPINSIGHTS_CONNECTION_STRING` is set
2. ✅ Variable is not marked as secret and visible in logs (first 10 chars)
3. ✅ Wait 2-5 minutes after pipeline completes
4. ✅ Check correct App Insights resource in Azure Portal
5. ✅ Try time range `ago(1h)` or `ago(24h)`

**Debug Query:**
```kusto
traces
| where timestamp > ago(24h)
| take 100
| project timestamp, message
| order by timestamp desc
```

### Issue: "APPINSIGHTS_CONNECTION_STRING not found"

- Verify variable name matches exactly (case-sensitive)
- Check variable is available in the scope/stage
- Try adding to Pipeline Library for global access

### Issue: Only seeing test logs, not real translation logs

- Verify `opencensus-ext-azure` is installed in Phase 2
- Check Phase 2 logs for "Azure Application Insights configured" message
- Verify translation.py is using updated version with env variable support

---

## 📚 Additional Resources

- **Full Query Collection**: See `ApplicationInsights-Queries.md`
- **Detailed Setup Guide**: See `SETUP-APPLICATION-INSIGHTS.md`
- **Quick Reference**: See `APP-INSIGHTS-QUICKSTART.md`

---

## ✨ You're All Set!

Your pipeline is configured to automatically send telemetry to Application Insights on every run. Just:

1. ✅ Set the `APPINSIGHTS_CONNECTION_STRING` variable in DevOps
2. ✅ Run your pipeline
3. ✅ Wait 2-5 minutes
4. ✅ View logs in Azure Portal

No local setup needed! Everything runs in Azure DevOps. 🚀

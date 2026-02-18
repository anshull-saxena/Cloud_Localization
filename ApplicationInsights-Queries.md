# Azure Application Insights Queries
## Localization Translation System Analytics

This document contains Kusto Query Language (KQL) queries for analyzing your localization translation pipeline in Azure Application Insights.

---

## 1. Basic Log Queries

### View All Translation Metrics
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend File = tostring(customDimensions.File)
| extend Lang = tostring(customDimensions.Lang)
| extend Segments = toint(customDimensions.Segments)
| extend TMHits = toint(customDimensions.TMHits)
| extend NMTCalls = toint(customDimensions.NMTCalls)
| extend AvgLatency = toreal(customDimensions.AvgLatency)
| extend TotalTime = toreal(customDimensions.TotalTime)
| project timestamp, File, Lang, Segments, TMHits, NMTCalls, AvgLatency, TotalTime
| order by timestamp desc
```

### View All Application Logs (Last 24 Hours)
```kusto
traces
| where timestamp > ago(24h)
| project timestamp, message, severityLevel, customDimensions
| order by timestamp desc
```

### View All Errors
```kusto
traces
| where timestamp > ago(7d)
| where severityLevel >= 3  // Warning and above
| project timestamp, severityLevel, message, customDimensions
| order by timestamp desc
```

---

## 2. Translation Performance Analytics

### Average Translation Time by Language
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| extend TotalTime = toreal(customDimensions.TotalTime)
| summarize AvgTime = avg(TotalTime), TotalRuns = count() by Lang
| order by AvgTime desc
```

### Translation Volume by File
```kusto
traces
| where timestamp > ago(30d)
| where message contains "TranslationMetrics"
| extend File = tostring(customDimensions.File)
| extend Segments = toint(customDimensions.Segments)
| summarize TotalSegments = sum(Segments), TranslationCount = count() by File
| order by TotalSegments desc
```

### Cache Hit Rate by Language
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| extend TMHits = toint(customDimensions.TMHits)
| extend TotalSegments = toint(customDimensions.Segments)
| summarize TotalHits = sum(TMHits), TotalSegs = sum(TotalSegments) by Lang
| extend CacheHitRate = round(100.0 * TotalHits / TotalSegs, 2)
| project Lang, CacheHitRate, TotalHits, TotalSegs
| order by CacheHitRate desc
```

### NMT API Call Frequency
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend NMTCalls = toint(customDimensions.NMTCalls)
| extend Lang = tostring(customDimensions.Lang)
| summarize TotalNMTCalls = sum(NMTCalls), AvgCallsPerRun = avg(NMTCalls) by Lang
| order by TotalNMTCalls desc
```

---

## 3. Latency & Performance Monitoring

### Average NMT Latency Trends (Hourly)
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend AvgLatency = toreal(customDimensions.AvgLatency)
| extend Lang = tostring(customDimensions.Lang)
| summarize AvgLatency_ms = avg(AvgLatency * 1000) by bin(timestamp, 1h), Lang
| render timechart
```

### P50, P95, P99 Latency Percentiles
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend AvgLatency = toreal(customDimensions.AvgLatency)
| summarize 
    P50 = percentile(AvgLatency, 50),
    P95 = percentile(AvgLatency, 95),
    P99 = percentile(AvgLatency, 99)
| extend P50_ms = P50 * 1000, P95_ms = P95 * 1000, P99_ms = P99 * 1000
| project P50_ms, P95_ms, P99_ms
```

### Slowest Translation Jobs (Top 20)
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend File = tostring(customDimensions.File)
| extend Lang = tostring(customDimensions.Lang)
| extend TotalTime = toreal(customDimensions.TotalTime)
| extend Segments = toint(customDimensions.Segments)
| top 20 by TotalTime desc
| project timestamp, File, Lang, TotalTime, Segments
```

---

## 4. Throughput & Volume Analysis

### Daily Translation Volume
```kusto
traces
| where timestamp > ago(30d)
| where message contains "TranslationMetrics"
| extend Segments = toint(customDimensions.Segments)
| summarize TotalSegments = sum(Segments), JobCount = count() by bin(timestamp, 1d)
| render timechart
```

### Throughput by Language (Segments per Hour)
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| extend Segments = toint(customDimensions.Segments)
| extend TotalTime = toreal(customDimensions.TotalTime)
| summarize TotalSegments = sum(Segments), TotalTime_hrs = sum(TotalTime) / 3600 by Lang
| extend Throughput = TotalSegments / TotalTime_hrs
| project Lang, Throughput, TotalSegments
| order by Throughput desc
```

### Peak vs Off-Peak Activity
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Hour = datetime_part("hour", timestamp)
| extend Segments = toint(customDimensions.Segments)
| summarize TotalSegments = sum(Segments), JobCount = count() by Hour
| order by Hour asc
| render columnchart
```

---

## 5. Cost & Efficiency Optimization

### Translation Cost Estimation (Based on NMT Calls)
```kusto
// Assuming $0.01 per NMT API call (adjust based on your pricing)
traces
| where timestamp > ago(30d)
| where message contains "TranslationMetrics"
| extend NMTCalls = toint(customDimensions.NMTCalls)
| extend Lang = tostring(customDimensions.Lang)
| summarize TotalNMTCalls = sum(NMTCalls) by Lang
| extend EstimatedCost = TotalNMTCalls * 0.01
| project Lang, TotalNMTCalls, EstimatedCost
| order by EstimatedCost desc
```

### Cache Effectiveness Over Time
```kusto
traces
| where timestamp > ago(30d)
| where message contains "TranslationMetrics"
| extend TMHits = toint(customDimensions.TMHits)
| extend Segments = toint(customDimensions.Segments)
| summarize TotalHits = sum(TMHits), TotalSegments = sum(Segments) by bin(timestamp, 1d)
| extend CacheHitRate = 100.0 * TotalHits / TotalSegments
| project timestamp, CacheHitRate, TotalHits, TotalSegments
| render timechart
```

### Files with Lowest Cache Hit Rate (Optimization Candidates)
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend File = tostring(customDimensions.File)
| extend TMHits = toint(customDimensions.TMHits)
| extend Segments = toint(customDimensions.Segments)
| summarize TotalHits = sum(TMHits), TotalSegments = sum(Segments) by File
| extend CacheHitRate = 100.0 * TotalHits / TotalSegments
| where TotalSegments > 10  // Only files with meaningful volume
| order by CacheHitRate asc
| take 20
```

---

## 6. Error & Exception Monitoring

### Error Rate by Type
```kusto
traces
| where timestamp > ago(7d)
| where severityLevel >= 3
| summarize ErrorCount = count() by message
| order by ErrorCount desc
```

### Failed Translation Jobs
```kusto
traces
| where timestamp > ago(7d)
| where message contains "ERROR" or message contains "FAILED"
| extend File = tostring(customDimensions.File)
| extend Lang = tostring(customDimensions.Lang)
| project timestamp, severityLevel, message, File, Lang
| order by timestamp desc
```

### Timeout & SLA Violations
```kusto
traces
| where timestamp > ago(7d)
| where message contains "timeout" or message contains "SLA"
| project timestamp, severityLevel, message, customDimensions
| order by timestamp desc
```

---

## 7. Real-Time Monitoring Dashboard Queries

### Current Active Translation Jobs (Last 5 Minutes)
```kusto
traces
| where timestamp > ago(5m)
| where message contains "Processing" or message contains "Translating"
| project timestamp, message
| order by timestamp desc
```

### Translation Job Status Summary (Last Hour)
```kusto
traces
| where timestamp > ago(1h)
| where message contains "Complete" or message contains "ERROR"
| summarize 
    Successful = countif(message contains "Complete"),
    Failed = countif(message contains "ERROR")
| extend SuccessRate = 100.0 * Successful / (Successful + Failed)
```

### Live NMT API Health
```kusto
traces
| where timestamp > ago(15m)
| where message contains "HF API error"
| summarize ErrorCount = count(), LastError = max(timestamp)
| extend Status = iff(ErrorCount > 0, "Unhealthy", "Healthy")
```

---

## 8. Custom Aggregations for Reporting

### Weekly Translation Report
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| extend Segments = toint(customDimensions.Segments)
| extend TotalTime = toreal(customDimensions.TotalTime)
| extend NMTCalls = toint(customDimensions.NMTCalls)
| extend TMHits = toint(customDimensions.TMHits)
| summarize 
    TotalJobs = count(),
    TotalSegments = sum(Segments),
    TotalNMTCalls = sum(NMTCalls),
    TotalTMHits = sum(TMHits),
    TotalTime_hrs = sum(TotalTime) / 3600,
    Languages = dcount(Lang)
| extend 
    AvgSegmentsPerJob = TotalSegments / TotalJobs,
    CacheHitRate = 100.0 * TotalTMHits / TotalSegments,
    Throughput_SegPerHr = TotalSegments / TotalTime_hrs
```

### Language Support Coverage
```kusto
traces
| where timestamp > ago(30d)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| summarize 
    FirstTranslation = min(timestamp),
    LastTranslation = max(timestamp),
    TotalJobs = count()
    by Lang
| extend DaysSinceLastUse = datetime_diff('day', now(), LastTranslation)
| order by LastTranslation desc
```

---

## 9. Alert-Ready Queries

### High Latency Alert (>5 seconds average)
```kusto
traces
| where timestamp > ago(5m)
| where message contains "TranslationMetrics"
| extend AvgLatency = toreal(customDimensions.AvgLatency)
| where AvgLatency > 5.0
| summarize count()
```

### Low Cache Hit Rate Alert (<50%)
```kusto
traces
| where timestamp > ago(1h)
| where message contains "TranslationMetrics"
| extend TMHits = toint(customDimensions.TMHits)
| extend Segments = toint(customDimensions.Segments)
| summarize TotalHits = sum(TMHits), TotalSegments = sum(Segments)
| extend CacheHitRate = 100.0 * TotalHits / TotalSegments
| where CacheHitRate < 50
| project CacheHitRate
```

### High Error Rate Alert (>10 errors in last hour)
```kusto
traces
| where timestamp > ago(1h)
| where severityLevel >= 3
| summarize ErrorCount = count()
| where ErrorCount > 10
```

---

## 10. Usage Instructions

### How to Use These Queries:

1. **Navigate to Azure Portal** → Application Insights → Your Resource
2. Go to **Logs** section (left menu)
3. Copy and paste any query above
4. Click **Run** to execute
5. Adjust the time range using `ago(Xd)` where X is number of days

### Common Time Ranges:
- `ago(5m)` - Last 5 minutes
- `ago(1h)` - Last hour
- `ago(24h)` - Last day
- `ago(7d)` - Last 7 days
- `ago(30d)` - Last 30 days

### Creating Alerts:
1. Run any alert-ready query above
2. Click **New alert rule**
3. Configure threshold and notification

### Creating Dashboards:
1. Run any visualization query (with `render` clause)
2. Click **Pin to dashboard**
3. Select or create a dashboard

---

## 11. Advanced Analytics

### Correlation: Segments vs Processing Time
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Segments = toint(customDimensions.Segments)
| extend TotalTime = toreal(customDimensions.TotalTime)
| project Segments, TotalTime
| render scatterchart
```

### Language Complexity Analysis (Time per Segment)
```kusto
traces
| where timestamp > ago(7d)
| where message contains "TranslationMetrics"
| extend Lang = tostring(customDimensions.Lang)
| extend Segments = toint(customDimensions.Segments)
| extend TotalTime = toreal(customDimensions.TotalTime)
| extend TimePerSegment = TotalTime / Segments
| summarize AvgTimePerSegment = avg(TimePerSegment) by Lang
| order by AvgTimePerSegment desc
```

### Batch Translation Efficiency
```kusto
traces
| where timestamp > ago(7d)
| where message contains "Batch translating"
| extend BatchSize = extract(@"translating (\d+) items", 1, message)
| summarize AvgBatchSize = avg(toint(BatchSize)), TotalBatches = count()
```

---

## Connection String Required

Make sure your `config.json` includes:
```json
{
  "app_insights_connection_string": "InstrumentationKey=YOUR-KEY;IngestionEndpoint=https://..."
}
```

## Notes:
- All queries assume the custom dimensions structure from [translation.py](API_based_HFace_AppInsight/translation.py#L282-L290)
- Adjust time ranges and thresholds based on your SLA requirements
- Combine multiple queries for comprehensive dashboards
- Set up alerts on critical metrics for proactive monitoring

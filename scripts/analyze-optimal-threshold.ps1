# Script to analyze source files and recommend optimal SmallSentenceThreshold
# This helps determine the best threshold for small vs large sentence classification

param(
    [string]$ConfigPath = "config.json"
)

# Import utilities
. (Join-Path $PSScriptRoot "TokenUtils.ps1")

Write-Host "=== Sentence Threshold Analysis ===" -ForegroundColor Cyan
Write-Host ""

# Load config
$configFullPath = Join-Path (Split-Path $PSScriptRoot -Parent) $ConfigPath
if (!(Test-Path $configFullPath)) {
    Write-Error "Config file not found: $configFullPath"
    exit 1
}

$config = Get-Content $configFullPath | ConvertFrom-Json

# Get source files
$sourceRepoPath = Join-Path (Split-Path $PSScriptRoot -Parent) $config.SourceRepoPath
if (!(Test-Path $sourceRepoPath)) {
    Write-Error "Source folder not found: $sourceRepoPath"
    exit 1
}

$resxFiles = Get-ChildItem -Path $sourceRepoPath -Filter "*.resx"
Write-Host "Analyzing $($resxFiles.Count) .resx files..." -ForegroundColor Yellow
Write-Host ""

# Collect all sentences
$allSentences = @()
$sentenceCharacterizations = @()

foreach ($file in $resxFiles) {
    try {
        $xml = [xml](Get-Content $file.FullName)
        foreach ($dataNode in $xml.root.data) {
            $text = $dataNode.Value
            if (![string]::IsNullOrWhiteSpace($text)) {
                $allSentences += $text
                
                # Characterize with current threshold
                $char = Get-SentenceCharacterization `
                    -Text $text `
                    -SmallThreshold $config.SmallSentenceThreshold `
                    -TokenizationMethod $config.TokenizationMethod
                
                $sentenceCharacterizations += $char
            }
        }
    } catch {
        Write-Warning "Failed to process $($file.Name): $_"
    }
}

Write-Host "Total sentences found: $($allSentences.Count)" -ForegroundColor Green
Write-Host ""

# Get statistics
$stats = Get-TokenStatistics -Characterizations $sentenceCharacterizations

# Display current analysis
Write-Host "=== Token Distribution ===" -ForegroundColor Cyan
Write-Host "Min tokens:     $($stats.MinTokens)"
Write-Host "Max tokens:     $($stats.MaxTokens)"
Write-Host "Mean tokens:    $($stats.MeanTokens)"
Write-Host "Median tokens:  $($stats.MedianTokens)"
Write-Host ""

Write-Host "=== Current Threshold: $($config.SmallSentenceThreshold) ===" -ForegroundColor Cyan
Write-Host "Small sentences: $($stats.SmallCount) ($([Math]::Round($stats.SmallCount/$stats.Count*100, 1))%)"
Write-Host "Large sentences: $($stats.LargeCount) ($([Math]::Round($stats.LargeCount/$stats.Count*100, 1))%)"
Write-Host ""

# Calculate percentile-based recommendations
$tokenCounts = $sentenceCharacterizations | ForEach-Object { $_.TokenCount } | Sort-Object

$p50 = $tokenCounts[[Math]::Floor($tokenCounts.Count * 0.50)]
$p75 = $tokenCounts[[Math]::Floor($tokenCounts.Count * 0.75)]
$p90 = $tokenCounts[[Math]::Floor($tokenCounts.Count * 0.90)]
$p95 = $tokenCounts[[Math]::Floor($tokenCounts.Count * 0.95)]

Write-Host "=== Percentile Analysis ===" -ForegroundColor Cyan
Write-Host "P50 (median):  $p50 tokens"
Write-Host "P75:           $p75 tokens"
Write-Host "P90:           $p90 tokens"
Write-Host "P95:           $p95 tokens"
Write-Host ""

# Recommendations
Write-Host "=== 💡 Recommendations ===" -ForegroundColor Yellow
Write-Host ""

Write-Host "Choose threshold based on your goals:" -ForegroundColor White
Write-Host ""

Write-Host "1. Balanced (50/50 split)" -ForegroundColor Green
Write-Host "   SmallSentenceThreshold: $p50"
Write-Host "   → 50% small, 50% large"
Write-Host ""

Write-Host "2. Conservative (75% small)" -ForegroundColor Green
Write-Host "   SmallSentenceThreshold: $p75"
Write-Host "   → Use NMT for most, LLM for complex"
Write-Host ""

Write-Host "3. Aggressive (90% small)" -ForegroundColor Green
Write-Host "   SmallSentenceThreshold: $p90"
Write-Host "   → Use NMT for almost all, LLM for edge cases"
Write-Host ""

Write-Host "4. Very Aggressive (95% small)" -ForegroundColor Green
Write-Host "   SmallSentenceThreshold: $p95"
Write-Host "   → Minimize LLM usage (cost optimization)"
Write-Host ""

# Show distribution by size buckets
Write-Host "=== Distribution by Token Count ===" -ForegroundColor Cyan
$buckets = @{
    "0-25"     = ($tokenCounts | Where-Object { $_ -le 25 }).Count
    "26-50"    = ($tokenCounts | Where-Object { $_ -gt 25 -and $_ -le 50 }).Count
    "51-100"   = ($tokenCounts | Where-Object { $_ -gt 50 -and $_ -le 100 }).Count
    "101-200"  = ($tokenCounts | Where-Object { $_ -gt 100 -and $_ -le 200 }).Count
    "201-500"  = ($tokenCounts | Where-Object { $_ -gt 200 -and $_ -le 500 }).Count
    "500+"     = ($tokenCounts | Where-Object { $_ -gt 500 }).Count
}

foreach ($bucket in $buckets.GetEnumerator() | Sort-Object Name) {
    $pct = [Math]::Round($bucket.Value / $stats.Count * 100, 1)
    $bar = "█" * [Math]::Min(50, [Math]::Floor($pct))
    Write-Host ("{0,-10} {1,5} ({2,5}%) {3}" -f $bucket.Key, $bucket.Value, $pct, $bar)
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. Choose a threshold from the recommendations above"
Write-Host "2. Update config.json: 'SmallSentenceThreshold': YOUR_VALUE"
Write-Host "3. If using model routing, ensure endpoints are configured"
Write-Host "4. Run the pipeline and monitor SLA logs for performance"
Write-Host ""

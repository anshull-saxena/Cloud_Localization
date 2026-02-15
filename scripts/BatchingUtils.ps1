# BatchingUtils.ps1
# Adaptive batch sizing utilities for localization pipeline
# Author: Localization Pipeline Refactoring
# Purpose: Create token-aware batches that respect semantic boundaries

<#
.SYNOPSIS
    Utility module for adaptive batch creation based on token budgets

.DESCRIPTION
    This module provides functions to:
    - Create batches with token budget constraints
    - Ensure semantic boundaries (never split sentences)
    - Compute batch metrics and statistics
    - Support research instrumentation

.NOTES
    Research Instrumentation: All batching decisions are logged for analysis
#>

# Import dependencies
. "$PSScriptRoot\TokenUtils.ps1"

<#
.SYNOPSIS
    Creates adaptive batches from sentences based on token budget

.DESCRIPTION
    Groups sentences into batches while respecting:
    - Maximum token budget per batch
    - Semantic boundaries (sentences are never split)
    - Configurable batch size limits

.PARAMETER Sentences
    Array of sentence objects with Text property

.PARAMETER MaxTokenBatch
    Maximum tokens allowed per batch (default: 2000)

.PARAMETER TokenizationMethod
    Method for token counting (default: CharacterBased)

.PARAMETER SmallThreshold
    Threshold for sentence characterization (default: 100)

.OUTPUTS
    Array of batch objects, each containing:
    - BatchId: Unique identifier
    - Sentences: Array of sentence objects
    - TotalTokens: Total token count for batch
    - SentenceCount: Number of sentences in batch

.EXAMPLE
    $sentences = @(
        @{ Id = "1"; Text = "Hello world" },
        @{ Id = "2"; Text = "This is a test" }
    )
    New-AdaptiveBatch -Sentences $sentences -MaxTokenBatch 1000
#>
function New-AdaptiveBatch {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$Sentences,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxTokenBatch = 2000,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CharacterBased", "APIBased")]
        [string]$TokenizationMethod = "CharacterBased",
        
        [Parameter(Mandatory=$false)]
        [string]$TokenizerAPIEndpoint = "",
        
        [Parameter(Mandatory=$false)]
        [int]$SmallThreshold = 100
    )
    
    if ($Sentences.Count -eq 0) {
        Write-Warning "No sentences provided for batching"
        return @()
    }
    
    Write-Verbose "Starting adaptive batching for $($Sentences.Count) sentences with max $MaxTokenBatch tokens per batch"
    
    $batches = @()
    $currentBatch = @{
        BatchId = 1
        Sentences = @()
        TotalTokens = 0
        SentenceCount = 0
        StartTime = Get-Date
    }
    
    foreach ($sentence in $Sentences) {
        # Get token count for this sentence
        $tokenCount = Get-TokenCount -Text $sentence.Text -Method $TokenizationMethod -APIEndpoint $TokenizerAPIEndpoint
        
        # Get sentence characterization
        $characterization = Get-SentenceCharacterization `
            -Text $sentence.Text `
            -SmallThreshold $SmallThreshold `
            -TokenizationMethod $TokenizationMethod `
            -TokenizerAPIEndpoint $TokenizerAPIEndpoint
        
        # Add characterization to sentence object
        $enrichedSentence = $sentence.PSObject.Copy()
        Add-Member -InputObject $enrichedSentence -NotePropertyName "TokenCount" -NotePropertyValue $tokenCount -Force
        Add-Member -InputObject $enrichedSentence -NotePropertyName "SizeCategory" -NotePropertyValue $characterization.SizeCategory -Force
        
        # Check if adding this sentence would exceed the batch limit
        $wouldExceedLimit = ($currentBatch.TotalTokens + $tokenCount) -gt $MaxTokenBatch
        
        if ($wouldExceedLimit -and $currentBatch.SentenceCount -gt 0) {
            # Finalize current batch
            $currentBatch.EndTime = Get-Date
            $currentBatch.Duration = ($currentBatch.EndTime - $currentBatch.StartTime).TotalMilliseconds
            
            $batches += [PSCustomObject]$currentBatch
            
            Write-Verbose "Batch $($currentBatch.BatchId) finalized: $($currentBatch.SentenceCount) sentences, $($currentBatch.TotalTokens) tokens"
            
            # Start new batch
            $currentBatch = @{
                BatchId = $batches.Count + 1
                Sentences = @()
                TotalTokens = 0
                SentenceCount = 0
                StartTime = Get-Date
            }
        }
        
        # Add sentence to current batch
        $currentBatch.Sentences += $enrichedSentence
        $currentBatch.TotalTokens += $tokenCount
        $currentBatch.SentenceCount++
    }
    
    # Finalize last batch if it has sentences
    if ($currentBatch.SentenceCount -gt 0) {
        $currentBatch.EndTime = Get-Date
        $currentBatch.Duration = ($currentBatch.EndTime - $currentBatch.StartTime).TotalMilliseconds
        $batches += [PSCustomObject]$currentBatch
        
        Write-Verbose "Batch $($currentBatch.BatchId) finalized: $($currentBatch.SentenceCount) sentences, $($currentBatch.TotalTokens) tokens"
    }
    
    Write-Verbose "Adaptive batching complete: $($batches.Count) batches created from $($Sentences.Count) sentences"
    
    return $batches
}

<#
.SYNOPSIS
    Computes metrics and statistics for batches

.DESCRIPTION
    Analyzes batch distribution and provides insights for optimization

.PARAMETER Batches
    Array of batch objects from New-AdaptiveBatch

.OUTPUTS
    PSCustomObject with batch metrics including:
    - BatchCount: Total number of batches
    - TotalSentences: Total sentences across all batches
    - TotalTokens: Total tokens across all batches
    - AvgTokensPerBatch: Average tokens per batch
    - MaxTokensInBatch: Maximum tokens in any batch
    - MinTokensInBatch: Minimum tokens in any batch
    - AvgSentencesPerBatch: Average sentences per batch

.EXAMPLE
    $batches = New-AdaptiveBatch -Sentences $sentences
    Get-BatchMetrics -Batches $batches
#>
function Get-BatchMetrics {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$Batches
    )
    
    if ($Batches.Count -eq 0) {
        Write-Warning "No batches provided for metrics calculation"
        return $null
    }
    
    $totalSentences = ($Batches | ForEach-Object { $_.SentenceCount } | Measure-Object -Sum).Sum
    $totalTokens = ($Batches | ForEach-Object { $_.TotalTokens } | Measure-Object -Sum).Sum
    $tokenCounts = $Batches | ForEach-Object { $_.TotalTokens }
    $sentenceCounts = $Batches | ForEach-Object { $_.SentenceCount }
    
    $metrics = [PSCustomObject]@{
        BatchCount = $Batches.Count
        TotalSentences = $totalSentences
        TotalTokens = $totalTokens
        AvgTokensPerBatch = [Math]::Round($totalTokens / $Batches.Count, 2)
        MaxTokensInBatch = ($tokenCounts | Measure-Object -Maximum).Maximum
        MinTokensInBatch = ($tokenCounts | Measure-Object -Minimum).Minimum
        AvgSentencesPerBatch = [Math]::Round($totalSentences / $Batches.Count, 2)
        MaxSentencesInBatch = ($sentenceCounts | Measure-Object -Maximum).Maximum
        MinSentencesInBatch = ($sentenceCounts | Measure-Object -Minimum).Minimum
        SmallSentenceCount = 0
        LargeSentenceCount = 0
    }
    
    # Count small vs large sentences
    foreach ($batch in $Batches) {
        foreach ($sentence in $batch.Sentences) {
            if ($sentence.SizeCategory -eq "small") {
                $metrics.SmallSentenceCount++
            } elseif ($sentence.SizeCategory -eq "large") {
                $metrics.LargeSentenceCount++
            }
        }
    }
    
    Write-Verbose "Batch metrics: $($metrics.BatchCount) batches, $($metrics.TotalTokens) tokens, avg $($metrics.AvgTokensPerBatch) tokens/batch"
    
    return $metrics
}

<#
.SYNOPSIS
    Exports batch information to JSON for analysis

.DESCRIPTION
    Saves batch details to a JSON file for research and debugging

.PARAMETER Batches
    Array of batch objects

.PARAMETER OutputPath
    Path to output JSON file

.EXAMPLE
    Export-BatchInfo -Batches $batches -OutputPath "logs/batches.json"
#>
function Export-BatchInfo {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$Batches,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Create export object
        $exportData = @{
            Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
            BatchCount = $Batches.Count
            Batches = $Batches
            Metrics = Get-BatchMetrics -Batches $Batches
        }
        
        # Export to JSON
        $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Verbose "Batch info exported to $OutputPath"
        return $true
    } catch {
        Write-Error "Failed to export batch info: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Validates batch configuration parameters

.DESCRIPTION
    Checks if batching parameters are within acceptable ranges

.PARAMETER MaxTokenBatch
    Maximum tokens per batch to validate

.OUTPUTS
    Boolean indicating if configuration is valid

.EXAMPLE
    Test-BatchConfiguration -MaxTokenBatch 2000
#>
function Test-BatchConfiguration {
    param(
        [Parameter(Mandatory=$true)]
        [int]$MaxTokenBatch
    )
    
    $isValid = $true
    $warnings = @()
    
    # Check if MaxTokenBatch is too small
    if ($MaxTokenBatch -lt 10) {
        $warnings += "MaxTokenBatch ($MaxTokenBatch) is very small. This may create excessive batches."
        $isValid = $false
    }
    
    # Check if MaxTokenBatch is too large
    if ($MaxTokenBatch -gt 100000) {
        $warnings += "MaxTokenBatch ($MaxTokenBatch) is very large. This may cause API timeouts."
    }
    
    # Log warnings
    foreach ($warning in $warnings) {
        Write-Warning $warning
    }
    
    return $isValid
}

<#
.SYNOPSIS
    Optimizes batch size based on historical performance

.DESCRIPTION
    Analyzes past batch performance and suggests optimal MaxTokenBatch value

.PARAMETER HistoricalBatches
    Array of historical batch objects with performance data

.OUTPUTS
    Recommended MaxTokenBatch value

.EXAMPLE
    $recommended = Get-OptimalBatchSize -HistoricalBatches $pastBatches
#>
function Get-OptimalBatchSize {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$HistoricalBatches
    )
    
    if ($HistoricalBatches.Count -eq 0) {
        Write-Warning "No historical data provided. Using default: 2000"
        return 2000
    }
    
    # Find batches with best performance (lowest duration per token)
    $batchesWithMetrics = $HistoricalBatches | Where-Object { 
        $_.Duration -and $_.TotalTokens -gt 0 
    } | ForEach-Object {
        [PSCustomObject]@{
            TotalTokens = $_.TotalTokens
            Duration = $_.Duration
            EfficiencyScore = $_.TotalTokens / $_.Duration  # tokens per ms
        }
    } | Sort-Object -Property EfficiencyScore -Descending
    
    if ($batchesWithMetrics.Count -eq 0) {
        Write-Warning "No valid performance data. Using default: 2000"
        return 2000
    }
    
    # Get median token count from top 25% most efficient batches
    $topPerformers = $batchesWithMetrics | Select-Object -First ([Math]::Max(1, [Math]::Floor($batchesWithMetrics.Count * 0.25)))
    $recommendedSize = ($topPerformers.TotalTokens | Measure-Object -Average).Average
    
    Write-Verbose "Optimal batch size recommendation: $([Math]::Round($recommendedSize)) tokens (based on $($topPerformers.Count) top performers)"
    
    return [Math]::Round($recommendedSize)
}

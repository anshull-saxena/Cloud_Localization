# TokenUtils.ps1
# Token counting and sentence characterization utilities for localization pipeline
# Author: Localization Pipeline Refactoring
# Purpose: Provide token-aware sentence analysis for adaptive batching and model routing

<#
.SYNOPSIS
    Utility module for token counting and sentence characterization

.DESCRIPTION
    This module provides functions to:
    - Estimate token counts for text strings
    - Characterize sentences as "small" or "large" based on token thresholds
    - Support both character-based approximation and API-based tokenization

.NOTES
    Research Instrumentation: All functions log detailed metrics for analysis
#>

# Import configuration
function Get-LocalizationConfig {
    param(
        [string]$ConfigPath = "config.json"
    )
    
    $configFullPath = Join-Path -Path (Resolve-Path "$PSScriptRoot\..").Path -ChildPath $ConfigPath
    
    if (Test-Path -Path $configFullPath) {
        return Get-Content -Path $configFullPath | ConvertFrom-Json
    } else {
        Write-Warning "Configuration file not found at $configFullPath. Using defaults."
        return $null
    }
}

<#
.SYNOPSIS
    Estimates token count for a given text string

.DESCRIPTION
    Provides token count estimation using configurable methods:
    - CharacterBased: Uses approximation (characters ÷ 4 ≈ tokens)
    - APIBased: Calls external tokenization API (if configured)

.PARAMETER Text
    The text string to analyze

.PARAMETER Method
    Tokenization method: "CharacterBased" or "APIBased"

.PARAMETER APIEndpoint
    Optional API endpoint for tokenization (required if Method is APIBased)

.OUTPUTS
    Integer representing estimated token count

.EXAMPLE
    Get-TokenCount -Text "Hello, world!" -Method "CharacterBased"
    Returns: 3
#>
function Get-TokenCount {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CharacterBased", "APIBased")]
        [string]$Method = "CharacterBased",
        
        [Parameter(Mandatory=$false)]
        [string]$APIEndpoint = ""
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 0
    }
    
    try {
        switch ($Method) {
            "CharacterBased" {
                # Character-based approximation: chars ÷ 4 ≈ tokens
                # This is a common heuristic for English text
                $charCount = $Text.Length
                $tokenEstimate = [Math]::Ceiling($charCount / 4.0)
                
                Write-Verbose "Token count (CharacterBased): $tokenEstimate tokens for $charCount characters"
                return $tokenEstimate
            }
            
            "APIBased" {
                if ([string]::IsNullOrWhiteSpace($APIEndpoint)) {
                    Write-Warning "APIBased tokenization requested but no endpoint provided. Falling back to CharacterBased."
                    return Get-TokenCount -Text $Text -Method "CharacterBased"
                }
                
                # Call external tokenization API
                try {
                    $headers = @{
                        'Content-Type' = 'application/json'
                    }
                    
                    $body = @{
                        'text' = $Text
                    } | ConvertTo-Json
                    
                    $response = Invoke-RestMethod -Method POST -Uri $APIEndpoint -Headers $headers -Body $body -TimeoutSec 5
                    
                    if ($response.token_count) {
                        Write-Verbose "Token count (APIBased): $($response.token_count) tokens"
                        return $response.token_count
                    } else {
                        Write-Warning "API response missing token_count field. Falling back to CharacterBased."
                        return Get-TokenCount -Text $Text -Method "CharacterBased"
                    }
                } catch {
                    Write-Warning "API tokenization failed: $_. Falling back to CharacterBased."
                    return Get-TokenCount -Text $Text -Method "CharacterBased"
                }
            }
            
            default {
                Write-Warning "Unknown tokenization method: $Method. Using CharacterBased."
                return Get-TokenCount -Text $Text -Method "CharacterBased"
            }
        }
    } catch {
        Write-Error "Error in Get-TokenCount: $_"
        return 0
    }
}

<#
.SYNOPSIS
    Characterizes a sentence as "small" or "large" based on token count

.DESCRIPTION
    Analyzes text and classifies it based on configurable token thresholds.
    Returns an object containing token count and size classification.

.PARAMETER Text
    The text string to characterize

.PARAMETER SmallThreshold
    Token count threshold for "small" classification (default: 100)

.PARAMETER TokenizationMethod
    Method to use for token counting (default: CharacterBased)

.PARAMETER TokenizerAPIEndpoint
    Optional API endpoint for tokenization

.OUTPUTS
    PSCustomObject with properties:
    - Text: Original text
    - TokenCount: Estimated token count
    - SizeCategory: "small" or "large"
    - Threshold: Threshold used for classification

.EXAMPLE
    Get-SentenceCharacterization -Text "This is a short sentence." -SmallThreshold 100
    Returns: @{ Text = "...", TokenCount = 6, SizeCategory = "small", Threshold = 100 }
#>
function Get-SentenceCharacterization {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$false)]
        [int]$SmallThreshold = 100,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CharacterBased", "APIBased")]
        [string]$TokenizationMethod = "CharacterBased",
        
        [Parameter(Mandatory=$false)]
        [string]$TokenizerAPIEndpoint = ""
    )
    
    try {
        # Get token count
        $tokenCount = Get-TokenCount -Text $Text -Method $TokenizationMethod -APIEndpoint $TokenizerAPIEndpoint
        
        # Classify based on threshold
        $sizeCategory = if ($tokenCount -le $SmallThreshold) { "small" } else { "large" }
        
        # Create characterization object
        $characterization = [PSCustomObject]@{
            Text = $Text
            TokenCount = $tokenCount
            SizeCategory = $sizeCategory
            Threshold = $SmallThreshold
            Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        }
        
        Write-Verbose "Sentence characterization: $sizeCategory ($tokenCount tokens, threshold: $SmallThreshold)"
        
        return $characterization
    } catch {
        Write-Error "Error in Get-SentenceCharacterization: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Batch characterizes multiple sentences

.DESCRIPTION
    Processes an array of sentences and returns characterization for each.
    Useful for batch processing and analytics.

.PARAMETER Sentences
    Array of text strings to characterize

.PARAMETER SmallThreshold
    Token count threshold for "small" classification

.PARAMETER TokenizationMethod
    Method to use for token counting

.OUTPUTS
    Array of characterization objects

.EXAMPLE
    $sentences = @("Short text", "This is a much longer sentence with many more words")
    Get-BatchSentenceCharacterization -Sentences $sentences -SmallThreshold 10
#>
function Get-BatchSentenceCharacterization {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Sentences,
        
        [Parameter(Mandatory=$false)]
        [int]$SmallThreshold = 100,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CharacterBased", "APIBased")]
        [string]$TokenizationMethod = "CharacterBased",
        
        [Parameter(Mandatory=$false)]
        [string]$TokenizerAPIEndpoint = ""
    )
    
    $characterizations = @()
    
    foreach ($sentence in $Sentences) {
        $char = Get-SentenceCharacterization `
            -Text $sentence `
            -SmallThreshold $SmallThreshold `
            -TokenizationMethod $TokenizationMethod `
            -TokenizerAPIEndpoint $TokenizerAPIEndpoint
        
        if ($char) {
            $characterizations += $char
        }
    }
    
    Write-Verbose "Batch characterization complete: $($characterizations.Count) sentences processed"
    
    return $characterizations
}

<#
.SYNOPSIS
    Gets token count statistics for a collection of sentences

.DESCRIPTION
    Computes aggregate statistics including min, max, mean, median, and percentiles

.PARAMETER Characterizations
    Array of characterization objects from Get-SentenceCharacterization

.OUTPUTS
    PSCustomObject with statistical metrics

.EXAMPLE
    $chars = Get-BatchSentenceCharacterization -Sentences $sentences
    Get-TokenStatistics -Characterizations $chars
#>
function Get-TokenStatistics {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$Characterizations
    )
    
    if ($Characterizations.Count -eq 0) {
        Write-Warning "No characterizations provided for statistics"
        return $null
    }
    
    $tokenCounts = $Characterizations | ForEach-Object { $_.TokenCount }
    $sortedTokens = $tokenCounts | Sort-Object
    
    $stats = [PSCustomObject]@{
        Count = $Characterizations.Count
        TotalTokens = ($tokenCounts | Measure-Object -Sum).Sum
        MinTokens = ($tokenCounts | Measure-Object -Minimum).Minimum
        MaxTokens = ($tokenCounts | Measure-Object -Maximum).Maximum
        MeanTokens = [Math]::Round(($tokenCounts | Measure-Object -Average).Average, 2)
        MedianTokens = $sortedTokens[[Math]::Floor($sortedTokens.Count / 2)]
        SmallCount = ($Characterizations | Where-Object { $_.SizeCategory -eq "small" }).Count
        LargeCount = ($Characterizations | Where-Object { $_.SizeCategory -eq "large" }).Count
    }
    
    Write-Verbose "Token statistics: $($stats.Count) sentences, $($stats.TotalTokens) total tokens, $($stats.MeanTokens) mean"
    
    return $stats
}

# Export module functions
Export-ModuleMember -Function @(
    'Get-LocalizationConfig',
    'Get-TokenCount',
    'Get-SentenceCharacterization',
    'Get-BatchSentenceCharacterization',
    'Get-TokenStatistics'
)

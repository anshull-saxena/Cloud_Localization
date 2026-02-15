# ModelRouter.ps1
# Hybrid model routing for NMT and LLM translation models
# Author: Localization Pipeline Refactoring
# Purpose: Route sentences to appropriate translation model based on size/complexity

<#
.SYNOPSIS
    Model routing abstraction for hybrid NMT/LLM translation

.DESCRIPTION
    This module provides functions to:
    - Route sentences to NMT or LLM models based on characterization
    - Invoke NMT translation endpoints
    - Invoke LLM translation endpoints
    - Provide unified translation interface with routing
    - Log all routing decisions for research

.NOTES
    Research Instrumentation: All routing decisions and model invocations are logged
#>

# Import dependencies
. (Join-Path $PSScriptRoot "TokenUtils.ps1")

<#
.SYNOPSIS
    Determines which model to use for translation

.DESCRIPTION
    Routes based on sentence characterization (small vs large)
    Logs routing decision for research analysis

.PARAMETER SentenceCharacterization
    Characterization object from Get-SentenceCharacterization

.PARAMETER SmallSentenceModel
    Model to use for small sentences (default: "NMT")

.PARAMETER LargeSentenceModel
    Model to use for large sentences (default: "LLM")

.OUTPUTS
    PSCustomObject with routing decision:
    - ModelType: "NMT" or "LLM"
    - Reason: Explanation for routing decision
    - SizeCategory: Original size category

.EXAMPLE
    $char = Get-SentenceCharacterization -Text "Hello world"
    Get-ModelRoute -SentenceCharacterization $char
#>
function Get-ModelRoute {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SentenceCharacterization,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("NMT", "LLM")]
        [string]$SmallSentenceModel = "NMT",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("NMT", "LLM")]
        [string]$LargeSentenceModel = "LLM"
    )
    
    $sizeCategory = $SentenceCharacterization.SizeCategory
    $tokenCount = $SentenceCharacterization.TokenCount
    
    # Determine model based on size category
    $modelType = if ($sizeCategory -eq "small") { $SmallSentenceModel } else { $LargeSentenceModel }
    
    $route = [PSCustomObject]@{
        ModelType = $modelType
        SizeCategory = $sizeCategory
        TokenCount = $tokenCount
        Reason = "Sentence classified as $sizeCategory ($tokenCount tokens), routing to $modelType"
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    }
    
    Write-Verbose "Model routing: $($route.Reason)"
    
    return $route
}

<#
.SYNOPSIS
    Invokes NMT translation model

.DESCRIPTION
    Calls NMT endpoint (defaults to Azure Cognitive Services Translator)
    Supports custom NMT endpoints if configured

.PARAMETER Text
    Text to translate

.PARAMETER SourceLanguage
    Source language code (e.g., "en")

.PARAMETER TargetLanguage
    Target language code (e.g., "fr-FR")

.PARAMETER NMTEndpoint
    NMT API endpoint URL

.PARAMETER NMTAPIKey
    NMT API authentication key

.PARAMETER AzureRegion
    Azure region for Cognitive Services

.OUTPUTS
    Translated text string

.EXAMPLE
    Invoke-NMTTranslation -Text "Hello" -SourceLanguage "en" -TargetLanguage "fr" -NMTAPIKey $key
#>
function Invoke-NMTTranslation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$true)]
        [string]$SourceLanguage,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetLanguage,
        
        [Parameter(Mandatory=$false)]
        [string]$NMTEndpoint = "",
        
        [Parameter(Mandatory=$true)]
        [string]$NMTAPIKey,
        
        [Parameter(Mandatory=$false)]
        [string]$AzureRegion = "eastus"
    )
    
    try {
        # Default to Azure Cognitive Services Translator if no custom endpoint
        if ([string]::IsNullOrWhiteSpace($NMTEndpoint)) {
            $NMTEndpoint = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=$SourceLanguage&to=$TargetLanguage"
        }
        
        $headers = @{
            'Ocp-Apim-Subscription-Key' = $NMTAPIKey
            'Ocp-Apim-Subscription-Region' = $AzureRegion
            'Content-Type' = 'application/json'
        }
        
        $body = @{'Text' = $Text} | ConvertTo-Json
        
        Write-Verbose "Invoking NMT translation: $($Text.Length) chars, $SourceLanguage -> $TargetLanguage"
        
        $response = Invoke-RestMethod -Method POST -Uri $NMTEndpoint -Headers $headers -Body "[$body]" -TimeoutSec 30
        
        $translatedText = $response.translations[0].text
        
        Write-Verbose "NMT translation complete: $($translatedText.Length) chars"
        
        return $translatedText
    } catch {
        Write-Error "NMT translation failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Invokes LLM translation model

.DESCRIPTION
    Calls LLM endpoint (e.g., Azure OpenAI GPT-4) for translation
    Uses prompt engineering for high-quality translation

.PARAMETER Text
    Text to translate

.PARAMETER SourceLanguage
    Source language code

.PARAMETER TargetLanguage
    Target language code

.PARAMETER LLMEndpoint
    LLM API endpoint URL

.PARAMETER LLMAPIKey
    LLM API authentication key

.PARAMETER LLMModelName
    Model name/identifier (e.g., "gpt-4")

.OUTPUTS
    Translated text string

.EXAMPLE
    Invoke-LLMTranslation -Text "Complex sentence" -SourceLanguage "en" -TargetLanguage "fr" -LLMAPIKey $key
#>
function Invoke-LLMTranslation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$true)]
        [string]$SourceLanguage,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetLanguage,
        
        [Parameter(Mandatory=$false)]
        [string]$LLMEndpoint = "",
        
        [Parameter(Mandatory=$false)]
        [string]$LLMAPIKey = "",
        
        [Parameter(Mandatory=$false)]
        [string]$LLMModelName = "gpt-4"
    )
    
    try {
        # Check if LLM endpoint is configured
        if ([string]::IsNullOrWhiteSpace($LLMEndpoint) -or [string]::IsNullOrWhiteSpace($LLMAPIKey)) {
            Write-Warning "LLM endpoint not configured. Falling back to NMT."
            throw "LLM endpoint not configured"
        }
        
        # Construct translation prompt
        $prompt = @"
Translate the following text from $SourceLanguage to $TargetLanguage. 
Preserve formatting, tone, and context. Only return the translated text, nothing else.

Text to translate:
$Text
"@
        
        # Prepare request for Azure OpenAI format
        $headers = @{
            'api-key' = $LLMAPIKey
            'Content-Type' = 'application/json'
        }
        
        $body = @{
            messages = @(
                @{
                    role = "system"
                    content = "You are a professional translator. Translate text accurately while preserving meaning, tone, and formatting."
                },
                @{
                    role = "user"
                    content = $prompt
                }
            )
            max_tokens = 2000
            temperature = 0.3
            model = $LLMModelName
        } | ConvertTo-Json -Depth 10
        
        Write-Verbose "Invoking LLM translation: $($Text.Length) chars, $SourceLanguage -> $TargetLanguage, model: $LLMModelName"
        
        $response = Invoke-RestMethod -Method POST -Uri $LLMEndpoint -Headers $headers -Body $body -TimeoutSec 60
        
        $translatedText = $response.choices[0].message.content.Trim()
        
        Write-Verbose "LLM translation complete: $($translatedText.Length) chars"
        
        return $translatedText
    } catch {
        Write-Error "LLM translation failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Unified translation interface with automatic routing

.DESCRIPTION
    Determines appropriate model and invokes translation
    Handles fallback logic if preferred model fails

.PARAMETER Text
    Text to translate

.PARAMETER SourceLanguage
    Source language code

.PARAMETER TargetLanguage
    Target language code

.PARAMETER EnableModelRouting
    Whether to enable hybrid routing (default: true)

.PARAMETER SmallThreshold
    Token threshold for small/large classification

.PARAMETER Config
    Configuration object with endpoint details

.OUTPUTS
    PSCustomObject with:
    - TranslatedText: The translation result
    - ModelUsed: Which model was used
    - RoutingDecision: Routing details
    - Duration: Translation time in milliseconds

.EXAMPLE
    $result = Invoke-TranslationWithRouting -Text "Hello" -SourceLanguage "en" -TargetLanguage "fr" -Config $config
#>
function Invoke-TranslationWithRouting {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        
        [Parameter(Mandatory=$true)]
        [string]$SourceLanguage,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetLanguage,
        
        [Parameter(Mandatory=$false)]
        [bool]$EnableModelRouting = $true,
        
        [Parameter(Mandatory=$false)]
        [int]$SmallThreshold = 100,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject]$Config = $null
    )
    
    $startTime = Get-Date
    
    try {
        # Get sentence characterization
        $characterization = Get-SentenceCharacterization -Text $Text -SmallThreshold $SmallThreshold
        
        # Determine routing
        $route = if ($EnableModelRouting) {
            Get-ModelRoute -SentenceCharacterization $characterization
        } else {
            [PSCustomObject]@{
                ModelType = "NMT"
                SizeCategory = "N/A"
                TokenCount = $characterization.TokenCount
                Reason = "Model routing disabled, using default NMT"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
            }
        }
        
        # Extract configuration
        $nmtAPIKey = if ($Config -and $Config.AzureCognitiveServiceAPIKey) { $Config.AzureCognitiveServiceAPIKey } else { "" }
        $nmtEndpoint = if ($Config -and $Config.NMTEndpoint) { $Config.NMTEndpoint } else { "" }
        $llmEndpoint = if ($Config -and $Config.LLMEndpoint) { $Config.LLMEndpoint } else { "" }
        $llmAPIKey = if ($Config -and $Config.LLMAPIKey) { $Config.LLMAPIKey } else { "" }
        $llmModelName = if ($Config -and $Config.LLMModelName) { $Config.LLMModelName } else { "gpt-4" }
        $azureRegion = if ($Config -and $Config.AzureRegion) { $Config.AzureRegion } else { "eastus" }
        
        # Invoke appropriate model with fallback
        $translatedText = $null
        $modelUsed = $route.ModelType
        
        try {
            if ($route.ModelType -eq "LLM") {
                $translatedText = Invoke-LLMTranslation `
                    -Text $Text `
                    -SourceLanguage $SourceLanguage `
                    -TargetLanguage $TargetLanguage `
                    -LLMEndpoint $llmEndpoint `
                    -LLMAPIKey $llmAPIKey `
                    -LLMModelName $llmModelName
            } else {
                $translatedText = Invoke-NMTTranslation `
                    -Text $Text `
                    -SourceLanguage $SourceLanguage `
                    -TargetLanguage $TargetLanguage `
                    -NMTEndpoint $nmtEndpoint `
                    -NMTAPIKey $nmtAPIKey `
                    -AzureRegion $azureRegion
            }
        } catch {
            # Fallback to NMT if LLM fails
            if ($route.ModelType -eq "LLM") {
                Write-Warning "LLM translation failed, falling back to NMT: $_"
                $translatedText = Invoke-NMTTranslation `
                    -Text $Text `
                    -SourceLanguage $SourceLanguage `
                    -TargetLanguage $TargetLanguage `
                    -NMTEndpoint $nmtEndpoint `
                    -NMTAPIKey $nmtAPIKey `
                    -AzureRegion $azureRegion
                $modelUsed = "NMT (fallback)"
            } else {
                throw
            }
        }
        
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $result = [PSCustomObject]@{
            TranslatedText = $translatedText
            ModelUsed = $modelUsed
            RoutingDecision = $route
            Duration = $duration
            TokenCount = $characterization.TokenCount
            SourceLength = $Text.Length
            TargetLength = $translatedText.Length
            Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        }
        
        Write-Verbose "Translation complete: $modelUsed, $duration ms, $($characterization.TokenCount) tokens"
        
        return $result
    } catch {
        Write-Error "Translation with routing failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Exports routing statistics for analysis

.DESCRIPTION
    Analyzes routing decisions and generates summary report

.PARAMETER RoutingDecisions
    Array of routing decision objects

.PARAMETER OutputPath
    Path to output JSON file

.EXAMPLE
    Export-RoutingStatistics -RoutingDecisions $decisions -OutputPath "logs/routing-stats.json"
#>
function Export-RoutingStatistics {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$RoutingDecisions,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        $nmtCount = ($RoutingDecisions | Where-Object { $_.ModelUsed -like "NMT*" }).Count
        $llmCount = ($RoutingDecisions | Where-Object { $_.ModelUsed -eq "LLM" }).Count
        $fallbackCount = ($RoutingDecisions | Where-Object { $_.ModelUsed -eq "NMT (fallback)" }).Count
        
        $stats = @{
            Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
            TotalTranslations = $RoutingDecisions.Count
            NMTCount = $nmtCount
            LLMCount = $llmCount
            FallbackCount = $fallbackCount
            NMTPercentage = [Math]::Round(($nmtCount / $RoutingDecisions.Count) * 100, 2)
            LLMPercentage = [Math]::Round(($llmCount / $RoutingDecisions.Count) * 100, 2)
            AvgDuration = [Math]::Round(($RoutingDecisions.Duration | Measure-Object -Average).Average, 2)
            AvgTokenCount = [Math]::Round(($RoutingDecisions.TokenCount | Measure-Object -Average).Average, 2)
            Decisions = $RoutingDecisions
        }
        
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        $stats | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Verbose "Routing statistics exported to $OutputPath"
        return $true
    } catch {
        Write-Error "Failed to export routing statistics: $_"
        return $false
    }
}

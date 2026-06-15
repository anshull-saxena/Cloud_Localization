# InfraRouter.ps1
# Infrastructure routing for VM vs Serverless execution
# Author: Localization Pipeline Refactoring
# Purpose: Optimize infrastructure utilization based on workload characteristics

<#
.SYNOPSIS
    Infrastructure routing module for hybrid VM/Serverless execution

.DESCRIPTION
    This module provides functions to:
    - Monitor current workload (concurrency, token load)
    - Route translation requests to VM or Serverless infrastructure
    - Track infrastructure utilization metrics
    - Optimize routing decisions based on thresholds

.NOTES
    This is an OPTIONAL feature, disabled by default
    Research Instrumentation: All routing decisions are logged
#>

# Global state for tracking concurrent requests
$script:ConcurrentRequests = @{}
$script:CurrentTokenLoad = 0
$script:RequestLock = New-Object System.Object

<#
.SYNOPSIS
    Gets current concurrent request count

.DESCRIPTION
    Tracks active translation requests for workload monitoring

.OUTPUTS
    Integer representing current concurrent requests

.EXAMPLE
    Get-CurrentConcurrentRequests
#>
function Get-CurrentConcurrentRequests {
    [System.Threading.Monitor]::Enter($script:RequestLock)
    try {
        # Clean up completed requests
        $now = Get-Date
        $expiredKeys = $script:ConcurrentRequests.Keys | Where-Object {
            ($now - $script:ConcurrentRequests[$_].StartTime).TotalSeconds -gt 300  # 5 min timeout
        }
        
        foreach ($key in $expiredKeys) {
            $script:ConcurrentRequests.Remove($key)
        }
        
        return $script:ConcurrentRequests.Count
    } finally {
        [System.Threading.Monitor]::Exit($script:RequestLock)
    }
}

<#
.SYNOPSIS
    Gets current token load across all active requests

.DESCRIPTION
    Sums token counts from all concurrent requests

.OUTPUTS
    Integer representing total tokens in flight

.EXAMPLE
    Get-CurrentTokenLoad
#>
function Get-CurrentTokenLoad {
    [System.Threading.Monitor]::Enter($script:RequestLock)
    try {
        $totalTokens = 0
        foreach ($request in $script:ConcurrentRequests.Values) {
            $totalTokens += $request.TokenCount
        }
        return $totalTokens
    } finally {
        [System.Threading.Monitor]::Exit($script:RequestLock)
    }
}

<#
.SYNOPSIS
    Registers a new translation request

.DESCRIPTION
    Adds request to tracking for workload monitoring

.PARAMETER RequestId
    Unique identifier for the request

.PARAMETER TokenCount
    Number of tokens in the request

.EXAMPLE
    Register-TranslationRequest -RequestId "req-123" -TokenCount 150
#>
function Register-TranslationRequest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequestId,
        
        [Parameter(Mandatory=$true)]
        [int]$TokenCount
    )
    
    [System.Threading.Monitor]::Enter($script:RequestLock)
    try {
        $script:ConcurrentRequests[$RequestId] = @{
            StartTime = Get-Date
            TokenCount = $TokenCount
        }
        
        Write-Verbose "Registered request $RequestId with $TokenCount tokens"
    } finally {
        [System.Threading.Monitor]::Exit($script:RequestLock)
    }
}

<#
.SYNOPSIS
    Unregisters a completed translation request

.DESCRIPTION
    Removes request from tracking

.PARAMETER RequestId
    Unique identifier for the request

.EXAMPLE
    Unregister-TranslationRequest -RequestId "req-123"
#>
function Unregister-TranslationRequest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequestId
    )
    
    [System.Threading.Monitor]::Enter($script:RequestLock)
    try {
        if ($script:ConcurrentRequests.ContainsKey($RequestId)) {
            $script:ConcurrentRequests.Remove($RequestId)
            Write-Verbose "Unregistered request $RequestId"
        }
    } finally {
        [System.Threading.Monitor]::Exit($script:RequestLock)
    }
}

<#
.SYNOPSIS
    Determines infrastructure routing decision

.DESCRIPTION
    Routes to VM or Serverless based on:
    - Current concurrency utilization
    - Current token load
    - Configurable thresholds

.PARAMETER ConcurrencyThreshold
    Max concurrent requests before routing to VM (default: 10)

.PARAMETER TokenLoadThreshold
    Max tokens in flight before routing to VM (default: 50000)

.OUTPUTS
    PSCustomObject with routing decision:
    - Infrastructure: "VM" or "Serverless"
    - Reason: Explanation for decision
    - CurrentConcurrency: Current concurrent request count
    - CurrentTokenLoad: Current token load

.EXAMPLE
    Get-InfrastructureRoute -ConcurrencyThreshold 10 -TokenLoadThreshold 50000
#>
function Get-InfrastructureRoute {
    param(
        [Parameter(Mandatory=$false)]
        [int]$ConcurrencyThreshold = 10,
        
        [Parameter(Mandatory=$false)]
        [int]$TokenLoadThreshold = 50000
    )
    
    $currentConcurrency = Get-CurrentConcurrentRequests
    $currentTokenLoad = Get-CurrentTokenLoad
    
    # Determine infrastructure based on thresholds
    $infrastructure = "Serverless"  # Default
    $reason = "Low workload"
    
    if ($currentConcurrency -gt $ConcurrencyThreshold) {
        $infrastructure = "VM"
        $reason = "High concurrency ($currentConcurrency > $ConcurrencyThreshold)"
    } elseif ($currentTokenLoad -gt $TokenLoadThreshold) {
        $infrastructure = "VM"
        $reason = "High token load ($currentTokenLoad > $TokenLoadThreshold)"
    }
    
    $route = [PSCustomObject]@{
        Infrastructure = $infrastructure
        Reason = $reason
        CurrentConcurrency = $currentConcurrency
        CurrentTokenLoad = $currentTokenLoad
        ConcurrencyThreshold = $ConcurrencyThreshold
        TokenLoadThreshold = $TokenLoadThreshold
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    }
    
    Write-Verbose "Infrastructure routing: $infrastructure ($reason)"
    
    return $route
}

<#
.SYNOPSIS
    Invokes translation on selected infrastructure

.DESCRIPTION
    Executes translation request on VM or Serverless endpoint
    Handles request registration and cleanup

.PARAMETER TranslationFunction
    ScriptBlock containing translation logic

.PARAMETER TokenCount
    Number of tokens in the request

.PARAMETER EnableInfraRouting
    Whether infrastructure routing is enabled

.PARAMETER Config
    Configuration object with endpoint details

.OUTPUTS
    Translation result with infrastructure metadata

.EXAMPLE
    $result = Invoke-TranslationOnInfra -TranslationFunction { ... } -TokenCount 150 -Config $config
#>
function Invoke-TranslationOnInfra {
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$TranslationFunction,
        
        [Parameter(Mandatory=$true)]
        [int]$TokenCount,
        
        [Parameter(Mandatory=$false)]
        [bool]$EnableInfraRouting = $false,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject]$Config = $null
    )
    
    $requestId = [Guid]::NewGuid().ToString()
    
    try {
        # Register request
        Register-TranslationRequest -RequestId $requestId -TokenCount $TokenCount
        
        # Determine infrastructure route
        $route = if ($EnableInfraRouting -and $Config) {
            $concurrencyThreshold = if ($Config.ConcurrencyThreshold) { $Config.ConcurrencyThreshold } else { 10 }
            $tokenLoadThreshold = if ($Config.TokenLoadThreshold) { $Config.TokenLoadThreshold } else { 50000 }
            
            Get-InfrastructureRoute -ConcurrencyThreshold $concurrencyThreshold -TokenLoadThreshold $tokenLoadThreshold
        } else {
            [PSCustomObject]@{
                Infrastructure = "Default"
                Reason = "Infrastructure routing disabled"
                CurrentConcurrency = Get-CurrentConcurrentRequests
                CurrentTokenLoad = Get-CurrentTokenLoad
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
            }
        }
        
        # Execute translation
        # Note: In a real implementation, this would route to different endpoints
        # For now, we execute the function directly and log the routing decision
        $startTime = Get-Date
        $result = & $TranslationFunction
        $endTime = Get-Date
        
        # Add infrastructure metadata to result
        if ($result -is [PSCustomObject]) {
            Add-Member -InputObject $result -NotePropertyName "InfrastructureUsed" -NotePropertyValue $route.Infrastructure -Force
            Add-Member -InputObject $result -NotePropertyName "InfraRoutingDecision" -NotePropertyValue $route -Force
        }
        
        Write-Verbose "Translation executed on $($route.Infrastructure) infrastructure"
        
        return $result
    } catch {
        Write-Error "Translation on infrastructure failed: $_"
        throw
    } finally {
        # Unregister request
        Unregister-TranslationRequest -RequestId $requestId
    }
}

<#
.SYNOPSIS
    Exports infrastructure routing statistics

.DESCRIPTION
    Analyzes routing decisions and generates summary report

.PARAMETER RoutingDecisions
    Array of infrastructure routing decision objects

.PARAMETER OutputPath
    Path to output JSON file

.EXAMPLE
    Export-InfraRoutingStatistics -RoutingDecisions $decisions -OutputPath "logs/infra-stats.json"
#>
function Export-InfraRoutingStatistics {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$RoutingDecisions,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        $vmCount = ($RoutingDecisions | Where-Object { $_.Infrastructure -eq "VM" }).Count
        $serverlessCount = ($RoutingDecisions | Where-Object { $_.Infrastructure -eq "Serverless" }).Count
        $defaultCount = ($RoutingDecisions | Where-Object { $_.Infrastructure -eq "Default" }).Count
        
        $stats = @{
            Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
            TotalRequests = $RoutingDecisions.Count
            VMCount = $vmCount
            ServerlessCount = $serverlessCount
            DefaultCount = $defaultCount
            VMPercentage = if ($RoutingDecisions.Count -gt 0) { [Math]::Round(($vmCount / $RoutingDecisions.Count) * 100, 2) } else { 0 }
            ServerlessPercentage = if ($RoutingDecisions.Count -gt 0) { [Math]::Round(($serverlessCount / $RoutingDecisions.Count) * 100, 2) } else { 0 }
            AvgConcurrency = [Math]::Round(($RoutingDecisions.CurrentConcurrency | Measure-Object -Average).Average, 2)
            AvgTokenLoad = [Math]::Round(($RoutingDecisions.CurrentTokenLoad | Measure-Object -Average).Average, 2)
            MaxConcurrency = ($RoutingDecisions.CurrentConcurrency | Measure-Object -Maximum).Maximum
            MaxTokenLoad = ($RoutingDecisions.CurrentTokenLoad | Measure-Object -Maximum).Maximum
            Decisions = $RoutingDecisions
        }
        
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        $stats | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Verbose "Infrastructure routing statistics exported to $OutputPath"
        return $true
    } catch {
        Write-Error "Failed to export infrastructure routing statistics: $_"
        return $false
    }
}

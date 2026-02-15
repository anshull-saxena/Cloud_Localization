param($Timer)

# Import new utility modules
. "$PSScriptRoot\TokenUtils.ps1"
. "$PSScriptRoot\BatchingUtils.ps1"
. "$PSScriptRoot\SLALogger.ps1"

$config = Get-Content -Path "config.json" | ConvertFrom-Json

try {
    Import-Module Az.Storage -ErrorAction Stop
} catch {
    Write-Error "Failed to import Azure Storage module: $_"
    exit
}

$sourceRepoPath = Join-Path -Path (Resolve-Path "$PSScriptRoot\..").Path -ChildPath $config.SourceRepoPath
$destinationContainerName = $config.TempContainerName
$connectionString = $config.ConnectionString
$targetLanguages = $config.TargetLanguages

# Extract new configuration parameters with defaults
$enableAdaptiveBatching = if ($config.EnableAdaptiveBatching -ne $null) { $config.EnableAdaptiveBatching } else { $true }
$maxTokenBatch = if ($config.MaxTokenBatch) { $config.MaxTokenBatch } else { 2000 }
$smallThreshold = if ($config.SmallSentenceThreshold) { $config.SmallSentenceThreshold } else { 100 }
$tokenizationMethod = if ($config.TokenizationMethod) { $config.TokenizationMethod } else { "CharacterBased" }
$enableSLALogging = if ($config.EnableSLALogging -ne $null) { $config.EnableSLALogging } else { $true }

# Initialize SLA logging if enabled
if ($enableSLALogging) {
    $runId = "function1-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Start-LocalizationRun -RunId $runId -Config $config | Out-Null
    Write-Host "Started SLA tracking for run: $runId"
}

try {
    if (!(Test-Path -Path $sourceRepoPath)) {
        Write-Error "Source repo path '$sourceRepoPath' does not exist."
        exit
    }

    Write-Host "Creating Azure Storage context..."
    $context = New-AzStorageContext -ConnectionString $connectionString -ErrorAction Stop
    
    Write-Host "Checking if container '$destinationContainerName' exists..."
    $containerExists = Get-AzStorageContainer -Name $destinationContainerName -Context $context -ErrorAction SilentlyContinue
    if (-not $containerExists) {
        Write-Host "Container does not exist. Creating container '$destinationContainerName'..."
        New-AzStorageContainer -Name $destinationContainerName -Context $context -Permission Off -ErrorAction Stop
        Write-Host "Container created successfully."
    } else {
        Write-Host "Container exists."
    }

    $sourceFiles = Get-ChildItem -Path $sourceRepoPath -Filter "*.resx"
    Write-Host "Found $($sourceFiles.Count) .resx files to process"

    foreach ($sourceFile in $sourceFiles) {
        try {
            $resxContent = [xml](Get-Content -Path $sourceFile.FullName)

            foreach ($language in $targetLanguages) {
                $languageStartTime = Get-Date
                
                # Collect all sentences from the .resx file
                $sentences = @()
                foreach ($dataNode in $resxContent.root.data) {
                    $key = $dataNode.Name
                    $value = $dataNode.Value
                    
                    $sentences += [PSCustomObject]@{
                        Id = $key
                        Text = $value
                    }
                }
                
                # Apply adaptive batching if enabled
                if ($enableAdaptiveBatching -and $sentences.Count -gt 0) {
                    Write-Verbose "Creating adaptive batches for $($sentences.Count) sentences (max $maxTokenBatch tokens per batch)"
                    
                    $batches = New-AdaptiveBatch `
                        -Sentences $sentences `
                        -MaxTokenBatch $maxTokenBatch `
                        -TokenizationMethod $tokenizationMethod `
                        -SmallThreshold $smallThreshold
                    
                    $batchMetrics = Get-BatchMetrics -Batches $batches
                    Write-Host "Created $($batchMetrics.BatchCount) batches for $($sourceFile.Name) ($language): avg $($batchMetrics.AvgTokensPerBatch) tokens/batch"
                    
                    # Log batch info if SLA logging is enabled
                    if ($enableSLALogging) {
                        $batchLogPath = "logs/batches-$($sourceFile.BaseName)-$language.json"
                        Export-BatchInfo -Batches $batches -OutputPath $batchLogPath | Out-Null
                    }
                }
                
                # Generate XLIFF content (preserving original format)
                $xliffContent = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
  <file source-language="en" target-language="' + $language + '" datatype="plaintext" original="' + $sourceFile.Name + '">
    <body>'

                # Add batch metadata as comments (research instrumentation, doesn't affect format)
                if ($enableAdaptiveBatching -and $batches) {
                    $xliffContent += "`n<!-- Adaptive Batching: $($batches.Count) batches, $($batchMetrics.TotalTokens) total tokens -->"
                }

                foreach ($dataNode in $resxContent.root.data) {
                    $key = $dataNode.Name
                    $value = $dataNode.Value

                    $xliffContent += "<trans-unit id='$key'><source><![CDATA[$value]]></source></trans-unit>"
                }

                $xliffContent += '</body></file></xliff>'

                $xliffFilePath = "xliff_$($sourceFile.BaseName)_$($language).xliff"
                $xliffContent | Out-File -FilePath $xliffFilePath -Encoding UTF8

                Write-Verbose "Uploading $xliffFilePath to blob storage..."
                try {
                    Set-AzStorageBlobContent -Container $destinationContainerName -File $xliffFilePath -Blob "$($sourceFile.BaseName)_$($language).xliff" -Context $context -Force -ErrorAction Stop
                    Write-Verbose "Successfully uploaded $xliffFilePath"
                } catch {
                    Write-Error "Failed to upload $xliffFilePath to Azure Blob Storage: $_"
                    throw
                }

                Remove-Item -Path $xliffFilePath -Force
                
                # Log language completion time if SLA logging is enabled
                if ($enableSLALogging) {
                    $languageEndTime = Get-Date
                    $languageCompletionMs = ($languageEndTime - $languageStartTime).TotalMilliseconds
                    
                    Add-LanguageMetric `
                        -LanguageCode $language `($sourceFile.Name) for language ${language}: $_"
            Write-Host "Error details: $($_.Exception.Message)"
            if ($_.Exception.InnerException) {
                Write-Host "Inner exception: $($_.Exception.InnerException.Message)"
            }
                        -SentenceCount $sentences.Count `
                        -TotalTokens $(if ($batchMetrics) { $batchMetrics.TotalTokens } else { 0 }) `
                        -CompletionTimeMs $languageCompletionMs | Out-Null
                }
            }
        } catch {
            Write-Error "Failed to process file ${sourceFile.Name} for language ${language}: $_"
        }
    }
    
    # Complete SLA logging if enabled
    if ($enableSLALogging) {
        Complete-LocalizationRun -SLADeadlineSeconds $config.SLADeadlineSeconds | Out-Null
        
        $slaLogPath = if ($config.SLALogPath) { $config.SLALogPath } else { "logs/sla-metrics-function1.json" }
        Export-SLAReport -OutputPath $slaLogPath | Out-Null
    }

} catch {
    Write-Error "An error occurred while processing .resx files: $_"
    exit
}
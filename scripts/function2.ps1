param($Timer)

$config = Get-Content -Path "config.json" | ConvertFrom-Json

# Import required modules
Import-Module Az.Storage

$inputContainerName = $config.TempContainerName
$connectionString = $config.ConnectionString
$azureCogSvcTranslateAPIKey = $config.AzureCognitiveServiceAPIKey
$azureRegion = $config.AzureRegion

# Set the relative path for the output folder in the main repository
$outputFolderPath = Join-Path -Path (Resolve-Path "$PSScriptRoot\..").Path -ChildPath $config.TargetRepoPath
if (!(Test-Path -Path $outputFolderPath)) {
    New-Item -ItemType Directory -Path $outputFolderPath | Out-Null
}

# Create a storage context using the connection string
$storageContext = New-AzStorageContext -ConnectionString $connectionString

# Function to translate content using Azure Translator Text API
function GetTranslation {
    param (
        [string]$TextToTranslate,
        [string]$SourceLanguage,
        [string]$TargetLanguage
    )

    # Build the request URI
    $translationServiceURI = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=$($SourceLanguage)&to=$($TargetLanguage)"

    # Request headers
    $RecoRequestHeader = @{
        'Ocp-Apim-Subscription-Key' = "$azureCogSvcTranslateAPIKey"
        'Ocp-Apim-Subscription-Region' = "$azureRegion"
        'Content-Type' = "application/json"
    }

    # Prepare the body of the request
    $TextToTranslate = @{'Text' = $TextToTranslate} | ConvertTo-Json

    # Send text to Azure for translation
    $RecoResponse = Invoke-RestMethod -Method POST -Uri $translationServiceURI -Headers $RecoRequestHeader -Body "[$TextToTranslate]"

    # Return the translated text
    return $RecoResponse.translations[0].text
}

function Convert-XLIFFToResx {
    param (
        [xml]$XLIFFContent,
        [string]$TargetLanguage
    )

    # Initialize .resx content
    $resxContent = '<?xml version="1.0" encoding="utf-8"?>
<root>'

    # Iterate over each <trans-unit> node in the XLIFF content
    foreach ($transUnitNode in $XLIFFContent.xliff.file.body.'trans-unit') {
        $id = $transUnitNode.id
        $sourceContent = $transUnitNode.source.InnerXml -replace '^\s*<\!\[CDATA\[', '' -replace '\]\]>\s*$'

        # Translate the source content to the target language
        $TargetLanguage = $TargetLanguage.Split('-')[0]
        $translatedContent = GetTranslation -TextToTranslate $sourceContent -SourceLanguage "en" -TargetLanguage $TargetLanguage

        # Add translated content to the .resx structure
        $resxContent += "<data name='$id' xml:lang='$TargetLanguage' xml:space='preserve'><value>$translatedContent</value></data>"
    }

    # Close .resx file
    $resxContent += '</root>'

    return $resxContent
}

try {
    $blobs = Get-AzStorageBlob -Container $inputContainerName -Context $storageContext
    foreach ($blob in $blobs) {
        if ($blob.Name -like "*.xliff") {
            Write-Host "Processing file: $($blob.Name)"

            $tempFile = New-TemporaryFile
            $xliffData = Get-AzStorageBlobContent -Container $inputContainerName -Blob $blob.Name -Context $storageContext -Destination $tempFile.FullName -Force

            $xliffContent = [xml](Get-Content -Path $tempFile.FullName -Raw)
            $targetLanguage = $xliffContent.xliff.file.'target-language'

            $resxContent = Convert-XLIFFToResx -XLIFFContent $xliffContent -TargetLanguage $targetLanguage
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($blob.Name)

            # Save translated .resx file locally
            $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath ("$baseName.resx")
            $resxContent | Out-File -FilePath $outputFilePath -Encoding UTF8

            Write-Host "Saved translated .resx file to: $outputFilePath"

            Remove-Item -Path $tempFile.FullName -Force
        }
    }
    Write-Host "Translation and conversion process completed."

    cd (Resolve-Path "$PSScriptRoot\..").Path

    $gitCredential = @"
url=https://dev.azure.com/SoftwareLocalization/_git/Localization
username=Ayush Kalra
password=$env:AZURE_DEVOPS_PAT
"@

    $gitCredential | git credential approve

    git add $config.TargetRepoPath
    git commit -m "Add translated .resx files to target folder after successful pipeline execution"
    git push origin main

    Write-Host "Successfully pushed the target folder to Azure repo."
}
catch {
    Write-Host "Error occurred: $_"
}

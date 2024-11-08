param($Timer)

$config = Get-Content -Path "config.json" | ConvertFrom-Json

# Import required modules
Import-Module Az.Storage

$inputContainerName = $config.TempContainerName
$outputContainerName = $config.OutputContainerName
$connectionString = $config.ConnectionString
$azureCogSvcTranslateAPIKey = $config.AzureCognitiveServiceAPIKey
$azureRegion = $config.AzureRegion

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

    # Return the converted text
    return $RecoResponse.translations[0].text
}

# Example text to translate
#$text = "Translating text from English to French"

# Translate the text from English to French
#$translatedText = GetTranslation -TextToTranslate $text -SourceLanguage "en" -TargetLanguage "fr"

# Output the translated text
#Write-Host "Translated Text: $translatedText"

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
        #Write-Host "$id"

        # Extract the inner text of the <source> tag, handling CDATA sections
        $sourceContent = $transUnitNode.source.InnerXml

        # Remove the CDATA section markers
        $sourceContent = $sourceContent -replace '^\s*<\!\[CDATA\[', ''
        $sourceContent = $sourceContent -replace '\]\]>\s*$', ''
        #Write-Host "$sourceContent"

        # Remove the region code if present
        $TargetLanguage = $TargetLanguage.Split('-')[0]
        #Write-Host "$TargetLanguage"

        # Translate the source content to the target language
        $translatedContent = GetTranslation -TextToTranslate $sourceContent -SourceLanguage "en" -TargetLanguage $TargetLanguage

        # Add the <trans-unit> node with translated content as a <data> element in .resx
        $resxContent += "<data name='$id' xml:lang='$TargetLanguage' xml:space='preserve'><value>$translatedContent</value></data>"
    }

    # Close .resx file
    $resxContent += '</root>'

    return $resxContent
}

# Get the input and output containers
try {
    $inputContainer = Get-AzStorageContainer -Name $inputContainerName -Context $storageContext -ErrorAction Stop
    $outputContainer = Get-AzStorageContainer -Name $outputContainerName -Context $storageContext -ErrorAction SilentlyContinue
    if (-not $outputContainer) {
        New-AzStorageContainer -Name $outputContainerName -Context $storageContext -Permission Container -ErrorAction Stop
    }
}
catch {
    Write-Host "Error occurred while accessing containers: $_"
    exit
}

# Iterate through the .xliff files in the input container
try {
    $blobs = Get-AzStorageBlob -Container $inputContainer.Name -Context $storageContext -ErrorAction Stop
    foreach ($blob in $blobs) {
        if ($blob.Name -like "*.xliff") {
            Write-Host "Processing file: $($blob.Name)"

            # Download the .xliff file to a temporary file
            try {
                $tempFile = New-TemporaryFile
                $xliffData = Get-AzStorageBlobContent -Container $inputContainer.Name -Blob $blob.Name -Context $storageContext -Destination $tempFile.FullName -Force -ErrorAction Stop
            }
            catch {
                Write-Host "Error occurred while downloading XLIFF file: $_"
                continue
            }

            # Convert the blob data to XLIFF content
            try {
                $xliffContent = [xml](Get-Content -Path $tempFile.FullName -Raw)
            }
            catch {
                Write-Host "Error occurred while reading XLIFF data from file: $_"
                continue
            }

            # Get the target language from the XLIFF file
            $targetLanguage = $xliffContent.xliff.file.'target-language'
            #Write-Host "$targetLanguage"

            # Convert XLIFF content to .resx format for the target language
            try {
                $resxContent = Convert-XLIFFToResx -XLIFFContent $xliffContent -TargetLanguage $targetLanguage
            }
            catch {
                Write-Host "Error occurred while converting XLIFF to RESX: $_"
                continue
            }

            # Get the base name of the .xliff file
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($blob.Name)

            # Upload the .resx content to the output container
            try {
                $outputBlobName = "{0}_{1}.resx" -f $baseName, $targetLanguage
                $outputBlob = $outputContainer.CloudBlobContainer.GetBlockBlobReference($outputBlobName)
                $outputBlob.UploadText($resxContent)
            }
            catch {
                Write-Host "Error occurred while uploading translated RESX file: $_"
                continue
            }
            
            # Remove the temporary file
            Remove-Item -Path $tempFile.FullName -Force
        }
    }
    Write-Host "Translation and conversion process completed."
}
catch {
    Write-Host "Error occurred: $_"
}
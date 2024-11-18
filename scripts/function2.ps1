param($Timer)

$config = Get-Content -Path "config.json" | ConvertFrom-Json

# Import required modules
Import-Module Az.Storage
Import-Module SqlServer

$inputContainerName = $config.TempContainerName
$connectionString = $config.ConnectionString
$azureCogSvcTranslateAPIKey = $config.AzureCognitiveServiceAPIKey
$azureRegion = $config.AzureRegion
$sqlConnectionString = $config.SQLConnectionString

# Set the relative path for the output folder in the main repository
$outputFolderPath = Join-Path -Path (Resolve-Path "$PSScriptRoot\..").Path -ChildPath $config.TargetRepoPath
if (!(Test-Path -Path $outputFolderPath)) {
    New-Item -ItemType Directory -Path $outputFolderPath | Out-Null
}

# Create a storage context using the connection string
$storageContext = New-AzStorageContext -ConnectionString $connectionString

# Function to retrieve translation from the SQL Database
function GetTranslationFromMemory {
    param (
        [string]$TextToTranslate,
        [string]$TargetCultureID
    )

    $query = "SELECT tt.TranslatedText FROM SourceText st JOIN TargetText tt ON st.SourceID = tt.SourceID WHERE st.SourceText = @TextToTranslate AND st.TargetCultureID = @TargetCultureID"
    
    $params = @{
        TextToTranslate = $TextToTranslate
        TargetCultureID = $TargetCultureID
    }

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $sqlConnectionString
    $command = $connection.CreateCommand()
    $command.CommandText = $query

    # Add parameters to prevent SQL injection
    foreach ($param in $params.Keys) {
        $sqlParam = $command.Parameters.Add("@$param", [System.Data.SqlDbType]::NVarChar)
        $sqlParam.Value = $params[$param]
    }

    $connection.Open()
    $result = $command.ExecuteScalar()
    $connection.Close()

    #Write-Host $result

    return $result
}

# Function to save new translation to the SQL Database
function SaveTranslationToMemory {
    param (
        [string]$TextToTranslate,
        [string]$TranslatedText,
        [string]$TargetCultureID
    )

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $sqlConnectionString
    $connection.Open()

    # Insert the source text if it does not exist
    $checkSourceQuery = "SELECT SourceID FROM SourceText WHERE SourceText = @TextToTranslate AND TargetCultureID = @TargetCultureID"
    $checkCommand = $connection.CreateCommand()
    $checkCommand.CommandText = $checkSourceQuery
    $checkCommand.Parameters.AddWithValue("@TextToTranslate", $TextToTranslate)
    $checkCommand.Parameters.AddWithValue("@TargetCultureID", $TargetCultureID)

    $sourceID = $checkCommand.ExecuteScalar()

    if (-not $sourceID) {
        $insertSourceQuery = "INSERT INTO SourceText (SourceText, TargetCultureID, CreatedAt) OUTPUT INSERTED.SourceID VALUES (@TextToTranslate, @TargetCultureID, GETDATE())"
        $insertCommand = $connection.CreateCommand()
        $insertCommand.CommandText = $insertSourceQuery
        $insertCommand.Parameters.AddWithValue("@TextToTranslate", $TextToTranslate)
        $insertCommand.Parameters.AddWithValue("@TargetCultureID", $TargetCultureID)

        $sourceID = $insertCommand.ExecuteScalar()
    }

    # Insert the translated text
    $insertTargetQuery = "INSERT INTO TargetText (SourceID, TranslatedText, UpdatedAt) VALUES (@SourceID, @TranslatedText, GETDATE())"
    $targetCommand = $connection.CreateCommand()
    $targetCommand.CommandText = $insertTargetQuery
    $targetCommand.Parameters.AddWithValue("@SourceID", $sourceID)
    $targetCommand.Parameters.AddWithValue("@TranslatedText", $TranslatedText)

    $targetCommand.ExecuteNonQuery()
    $connection.Close()
}

# Function to translate content using Azure Translator Text API
function GetTranslation {
    param (
        [string]$TextToTranslate,
        [string]$SourceLanguage,
        [string]$TargetLanguage,
        [string]$TargetCultureID
    )

    # Check translation memory first
    $cachedTranslation = GetTranslationFromMemory -TextToTranslate $TextToTranslate -TargetCultureID $TargetCultureID
    if ($cachedTranslation) {
        return $cachedTranslation
    }

    # Build the request URI
    $translationServiceURI = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=$($SourceLanguage)&to=$($TargetLanguage)"

    # Request headers
    $RecoRequestHeader = @{
        'Ocp-Apim-Subscription-Key' = "$azureCogSvcTranslateAPIKey"
        'Ocp-Apim-Subscription-Region' = "$azureRegion"
        'Content-Type' = "application/json"
    }

    # Prepare the body of the request
    $TextBody = @{'Text' = $TextToTranslate} | ConvertTo-Json

    # Send text to Azure for translation
    $RecoResponse = Invoke-RestMethod -Method POST -Uri $translationServiceURI -Headers $RecoRequestHeader -Body "[$TextBody]"

    # Get translated text
    $translatedText = $RecoResponse.translations[0].text
    #Write-Host $translatedText

    # Save the new translation to the memory
    SaveTranslationToMemory -TextToTranslate $TextToTranslate -TranslatedText $translatedText -TargetCultureID $TargetCultureID

    return $translatedText
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
        #Write-Host $sourceContent

        # Translate the source content to the target language
        $translatedContent = [string](GetTranslation -TextToTranslate $sourceContent -SourceLanguage "en" -TargetLanguage $TargetLanguage -TargetCultureID $TargetLanguage)
        #$translatedContent = $translatedContent -replace "@TextToTranslate @TargetCultureID ", ""
        $translatedContent = $translatedContent.Replace("@TextToTranslate @TargetCultureID @TextToTranslate @TargetCultureID @SourceID @TranslatedText 1 ", "")
        #Write-Host $translatedContent

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

    # git checkout main
    # git add .
    # git commit -m "Add translated .resx files to target folder after successful pipeline execution"
    # git pull origin main --rebase
    # git push origin main

    Write-Host "Successfully pushed the target folder to Azure repo."
}
catch {
    Write-Host "Error occurred: $_"
}
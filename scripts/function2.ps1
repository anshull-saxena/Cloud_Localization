param($Timer)

$config = Get-Content -Path "config.json" | ConvertFrom-Json

Import-Module Az.Storage
Import-Module SqlServer

$inputContainerName = $config.TempContainerName
$connectionString = $config.ConnectionString
$azureCogSvcTranslateAPIKey = $config.AzureCognitiveServiceAPIKey
$azureRegion = $config.AzureRegion
$sqlConnectionString = $config.SQLConnectionString

$outputFolderPath = Join-Path -Path (Resolve-Path "$PSScriptRoot\..").Path -ChildPath $config.TargetRepoPath
if (!(Test-Path -Path $outputFolderPath)) {
    New-Item -ItemType Directory -Path $outputFolderPath | Out-Null
}

$storageContext = New-AzStorageContext -ConnectionString $connectionString

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

    foreach ($param in $params.Keys) {
        $sqlParam = $command.Parameters.Add("@$param", [System.Data.SqlDbType]::NVarChar)
        $sqlParam.Value = $params[$param]
    }

    $connection.Open()
    $result = $command.ExecuteScalar()
    $connection.Close()

    return $result
}

function SaveTranslationToMemory {
    param (
        [string]$TextToTranslate,
        [string]$TranslatedText,
        [string]$TargetCultureID
    )

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $sqlConnectionString
    $connection.Open()

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

    $insertTargetQuery = "INSERT INTO TargetText (SourceID, TranslatedText, UpdatedAt) VALUES (@SourceID, @TranslatedText, GETDATE())"
    $targetCommand = $connection.CreateCommand()
    $targetCommand.CommandText = $insertTargetQuery
    $targetCommand.Parameters.AddWithValue("@SourceID", $sourceID)
    $targetCommand.Parameters.AddWithValue("@TranslatedText", $TranslatedText)

    $targetCommand.ExecuteNonQuery()
    $connection.Close()
}

function GetTranslation {
    param (
        [string]$TextToTranslate,
        [string]$SourceLanguage,
        [string]$TargetLanguage,
        [string]$TargetCultureID
    )

    $cachedTranslation = GetTranslationFromMemory -TextToTranslate $TextToTranslate -TargetCultureID $TargetCultureID
    if ($cachedTranslation) {
        return $cachedTranslation
    }

    $translationServiceURI = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=$($SourceLanguage)&to=$($TargetLanguage)"

    $RecoRequestHeader = @{
        'Ocp-Apim-Subscription-Key' = "$azureCogSvcTranslateAPIKey"
        'Ocp-Apim-Subscription-Region' = "$azureRegion"
        'Content-Type' = "application/json"
    }

    $TextBody = @{'Text' = $TextToTranslate} | ConvertTo-Json

    $RecoResponse = Invoke-RestMethod -Method POST -Uri $translationServiceURI -Headers $RecoRequestHeader -Body "[$TextBody]"

    $translatedText = $RecoResponse.translations[0].text
    SaveTranslationToMemory -TextToTranslate $TextToTranslate -TranslatedText $translatedText -TargetCultureID $TargetCultureID

    return $translatedText
}

function Convert-XLIFFToResx {
    param (
        [xml]$XLIFFContent,
        [string]$TargetLanguage
    )

    $resxContent = '<?xml version="1.0" encoding="utf-8"?>
<root>'

    foreach ($transUnitNode in $XLIFFContent.xliff.file.body.'trans-unit') {
        $id = $transUnitNode.id
        $sourceContent = $transUnitNode.source.InnerXml -replace '^\s*<\!\[CDATA\[', '' -replace '\]\]>\s*$'

        $translatedContent = [string](GetTranslation -TextToTranslate $sourceContent -SourceLanguage "en" -TargetLanguage $TargetLanguage -TargetCultureID $TargetLanguage)
        $translatedContent = $translatedContent.Replace("@TextToTranslate @TargetCultureID @TextToTranslate @TargetCultureID @SourceID @TranslatedText 1 ", "")

        $resxContent += "<data name='$id' xml:lang='$TargetLanguage' xml:space='preserve'><value>$translatedContent</value></data>"
    }

    $resxContent += '</root>'

    return $resxContent
}

try {
    cd (Resolve-Path "$PSScriptRoot\..").Path
    git checkout main
    git pull origin main --rebase

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

            $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath ("$baseName.resx")
            $resxContent | Out-File -FilePath $outputFilePath -Encoding UTF8

            Write-Host "Saved translated .resx file to: $outputFilePath"

            Remove-Item -Path $tempFile.FullName -Force
        }
    }
    Write-Host "Translation and conversion process completed."

    git add .
    git commit -m "Add translated .resx files to target folder after successful pipeline execution"
    git push origin main

    Write-Host "Successfully pushed the target folder to Azure repo."
}
catch {
    Write-Host "Error occurred: $_"
}
# Input bindings are passed in via param block.
param($Timer)

# Import the Azure Storage module
try {
    Import-Module Az.Storage -ErrorAction Stop
} catch {
    Write-Error "Failed to import Azure Storage module: $_"
    exit
}

# Define storage account and containers
$storageAccountName = "cloudlocalizationstorage"
$sourceContainerName = "resx-input-files"
$destinationContainerName = "xliff-temp-files"
$connectionString = "DefaultEndpointsProtocol=https;AccountName=cloudlocalizationstorage;AccountKey=5fSpWeghTLLgkIYx1D36b6i/8/6s40/7vE4rjglpTpHOze4NUu6ADJk6W70ca9xXagM7/ePI4Lqa+AStDYW5Ug==;EndpointSuffix=core.windows.net"

try {
    # Retrieve static.resx file content
    $context = New-AzStorageContext -ConnectionString $connectionString -ErrorAction Stop
    $sourceBlob = Get-AzStorageBlob -Container $sourceContainerName -Context $context -Blob "static.resx" -ErrorAction Stop

    # Loop through target languages and create xliff files
    $targetLanguages = @("en-US", "fr-FR", "es-ES") # Add more languages as needed
    foreach ($language in $targetLanguages) {
        try {
            # Create a temporary file to store the blob content
            $tempFile = [System.IO.Path]::GetTempFileName()

            # Download blob content to the temporary file
            $sourceBlob | Get-AzStorageBlobContent -Destination $tempFile -Context $context -Force -ErrorAction Stop

            # Parse the downloaded .resx file
            $resxContent = [xml](Get-Content -Path $tempFile)

            # Initialize XLIFF content for this language
            $xliffContent = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
  <file source-language="en" target-language="' + $language + '" datatype="plaintext" original="static.resx">
    <body>'

            # Iterate over each <data> node in the .resx file
            foreach ($dataNode in $resxContent.root.data) {
                $key = $dataNode.Name
                $value = $dataNode.Value

                # Add each <data> node as a <trans-unit> element in XLIFF
                $xliffContent += "<trans-unit id='$key'><source><![CDATA[$value]]></source></trans-unit>"
            }

            # Close XLIFF file
            $xliffContent += '</body></file></xliff>'

            # Specify local file path to upload
            $xliffFilePath = "xliff_$($language).xliff"
            $xliffContent | Out-File -FilePath $xliffFilePath -Encoding UTF8

            # Upload xliff file to destination container
            Set-AzStorageBlobContent -Container $destinationContainerName -File $xliffFilePath -Blob "static_$($language).xliff" -Context $context -Force -ErrorAction Stop

            # Optionally delete the local XLIFF file after uploading
            Remove-Item -Path $xliffFilePath -Force
        } catch {
            Write-Error "Failed to process language ${language}: $_"
        } finally {
            # Clean up temporary file
            Remove-Item -Path $tempFile -Force
        }
    }
} catch {
    Write-Error "Failed to retrieve static.resx file content: $_"
    exit
}

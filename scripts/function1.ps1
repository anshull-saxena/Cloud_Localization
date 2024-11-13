# Input bindings are passed in via param block.
param($Timer)

$config = Get-Content -Path "config.json" | ConvertFrom-Json

# Import the Azure Storage module
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

try {
    # Check if source repo path exists
    if (!(Test-Path -Path $sourceRepoPath)) {
        Write-Error "Source repo path '$sourceRepoPath' does not exist."
        exit
    }

    # Create a storage context
    $context = New-AzStorageContext -ConnectionString $connectionString -ErrorAction Stop

    # Get all .resx files from the local source repository
    $sourceFiles = Get-ChildItem -Path $sourceRepoPath -Filter "*.resx"

    # Process each .resx file in the source directory
    foreach ($sourceFile in $sourceFiles) {
        try {
            # Load .resx file content
            $resxContent = [xml](Get-Content -Path $sourceFile.FullName)

            # Loop through target languages and create .xliff files
            foreach ($language in $targetLanguages) {
                # Create XLIFF content for this language
                $xliffContent = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
  <file source-language="en" target-language="' + $language + '" datatype="plaintext" original="' + $sourceFile.Name + '">
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

                # Specify local file path for temporary storage
                $xliffFilePath = "xliff_$($sourceFile.BaseName)_$($language).xliff"
                $xliffContent | Out-File -FilePath $xliffFilePath -Encoding UTF8

                # Upload XLIFF file to destination blob container
                Set-AzStorageBlobContent -Container $destinationContainerName -File $xliffFilePath -Blob "$($sourceFile.BaseName)_$($language).xliff" -Context $context -Force -ErrorAction Stop

                # Clean up temporary XLIFF file after upload
                Remove-Item -Path $xliffFilePath -Force
            }
        } catch {
            Write-Error "Failed to process file ${sourceFile.Name} for language ${language}: $_"
        }
    }

} catch {
    Write-Error "An error occurred while processing .resx files: $_"
    exit
}
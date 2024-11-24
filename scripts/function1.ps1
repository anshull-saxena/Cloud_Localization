param($Timer)

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

try {
    if (!(Test-Path -Path $sourceRepoPath)) {
        Write-Error "Source repo path '$sourceRepoPath' does not exist."
        exit
    }

    $context = New-AzStorageContext -ConnectionString $connectionString -ErrorAction Stop

    $sourceFiles = Get-ChildItem -Path $sourceRepoPath -Filter "*.resx"

    foreach ($sourceFile in $sourceFiles) {
        try {
            $resxContent = [xml](Get-Content -Path $sourceFile.FullName)

            foreach ($language in $targetLanguages) {
                $xliffContent = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">
  <file source-language="en" target-language="' + $language + '" datatype="plaintext" original="' + $sourceFile.Name + '">
    <body>'

                foreach ($dataNode in $resxContent.root.data) {
                    $key = $dataNode.Name
                    $value = $dataNode.Value

                    $xliffContent += "<trans-unit id='$key'><source><![CDATA[$value]]></source></trans-unit>"
                }

                $xliffContent += '</body></file></xliff>'

                $xliffFilePath = "xliff_$($sourceFile.BaseName)_$($language).xliff"
                $xliffContent | Out-File -FilePath $xliffFilePath -Encoding UTF8

                Set-AzStorageBlobContent -Container $destinationContainerName -File $xliffFilePath -Blob "$($sourceFile.BaseName)_$($language).xliff" -Context $context -Force -ErrorAction Stop

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
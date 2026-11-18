# Resolve-VBRImportPath
# Returns the export folder an import should read. An explicit -InputPath is
# returned unchanged. Otherwise the export folders (those holding a
# _metadata.json) under <current dir>\output are listed: a single one is used
# directly, several are offered as a numbered list to choose from.

function Resolve-VBRImportPath {
    param(
        [string] $InputPath,
        [string] $OutputRoot = (Join-Path (Get-Location).Path 'output')
    )

    if ($InputPath) { return $InputPath }

    if (-not (Test-Path $OutputRoot -PathType Container)) {
        throw "No -InputPath given and '$OutputRoot' does not exist. Pass -InputPath with the export folder to import."
    }

    $folders = @(Get-Item $OutputRoot) + @(Get-ChildItem $OutputRoot -Directory)
    $exports = foreach ($folder in $folders) {
        $metaFile = Join-Path $folder.FullName '_metadata.json'
        if (-not (Test-Path $metaFile)) { continue }

        $meta = $null
        try { $meta = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }

        $exportedAt = $folder.LastWriteTime
        if ($meta.exportTimestamp) {
            $parsed = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse([string]$meta.exportTimestamp, [ref]$parsed)) {
                $exportedAt = $parsed.LocalDateTime
            }
        }

        [pscustomobject]@{
            Path         = $folder.FullName
            SourceServer = if ($meta.sourceServer) { $meta.sourceServer } else { '(unknown)' }
            ExportedAt   = $exportedAt
        }
    }
    $exports = @($exports | Sort-Object ExportedAt -Descending)

    if ($exports.Count -eq 0) {
        throw "No export folders (containing _metadata.json) found under '$OutputRoot'. Pass -InputPath with the export folder to import."
    }

    if ($exports.Count -eq 1) {
        Write-Host "Using the only export found: $($exports[0].Path)"
        return $exports[0].Path
    }

    Write-Host "Found $($exports.Count) exports under '$OutputRoot' (newest first):"
    for ($i = 0; $i -lt $exports.Count; $i++) {
        $e = $exports[$i]
        Write-Host ("  [{0}] {1}  exported {2:yyyy-MM-dd HH:mm:ss}  ({3})" -f ($i + 1), $e.SourceServer, $e.ExportedAt, $e.Path)
    }

    $choice = 0
    while ($choice -lt 1 -or $choice -gt $exports.Count) {
        $answer = Read-Host "Select the export to import [1-$($exports.Count)]"
        if (-not [int]::TryParse($answer, [ref]$choice)) { $choice = 0 }
    }

    $selected = $exports[$choice - 1].Path
    Write-Host "Using export: $selected"
    return $selected
}

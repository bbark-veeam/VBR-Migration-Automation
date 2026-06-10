# Export-VBRRepository
# Exports backup repository records from the source VBR server's automation
# API and writes them to Repositories.json.
#
# When -IsVSA is specified along with -SourceFQDN, repositories hosted on
# the source VSA itself are filtered out before being written to disk. A VSA
# appliance cannot be added as a managed server to another Veeam installation,
# so its local storage is not reachable from the target server.

function Export-VBRRepository {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting Repositories..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/repositories/export' `
        -Body       @{}

    if ($IsVSA -and $SourceFQDN) {
        $totalExcluded = 0
        foreach ($prop in @($result.PSObject.Properties)) {
            $items = @($prop.Value)
            if ($items.Count -eq 0) { continue }

            $kept = @($items | Where-Object {
                $_.hostName -ne $SourceFQDN
            })

            $excluded = $items.Count - $kept.Count
            if ($excluded -gt 0) {
                Write-Host "  Excluded $excluded $($prop.Name) hosted on source VSA ($SourceFQDN)."
                $result.($prop.Name) = $kept
                $totalExcluded += $excluded
            }
        }
        if ($totalExcluded -eq 0) {
            Write-Host "  No VSA-hosted repositories found to exclude."
        }
    }

    $outFile = Join-Path $OutputPath "Repositories.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

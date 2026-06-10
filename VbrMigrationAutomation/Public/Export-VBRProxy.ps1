# Export-VBRProxy
# Exports backup proxy records from the source VBR server's automation API
# and writes them to Proxies.json.

function Export-VBRProxy {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting Proxies..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/proxies/export' `
        -Body       @{}

    $outFile = Join-Path $OutputPath "Proxies.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

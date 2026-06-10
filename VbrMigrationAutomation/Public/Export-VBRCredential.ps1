# Export-VBRCredential
# Exports credential records from the source VBR server's automation API and
# writes them to Credentials.json in the specified output directory. Password
# values are omitted from the export by the Veeam API design — only metadata
# and uniqueId identifiers are preserved.

function Export-VBRCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting Credentials..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/credentials/export' `
        -Body       @{}

    $outFile = Join-Path $OutputPath "Credentials.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

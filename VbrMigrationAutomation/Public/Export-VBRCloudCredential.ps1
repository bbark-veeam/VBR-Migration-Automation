# Export-VBRCloudCredential
# Exports cloud credential records (Amazon, Azure, Google, etc.) from the
# source VBR server's automation API and writes them to CloudCredentials.json.
# Secret values (secretKey, sharedKey) are omitted by the Veeam API design.

function Export-VBRCloudCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting CloudCredentials..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/cloudcredentials/export' `
        -Body       @{}

    $outFile = Join-Path $OutputPath "CloudCredentials.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

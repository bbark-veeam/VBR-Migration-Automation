# Export-VBREncryptionPassword
# Exports encryption password metadata from the source VBR server's automation
# API and writes it to EncryptionPasswords.json. The Veeam API does not include
# the actual password values in the export — only metadata such as hint and
# uniqueId are preserved.

function Export-VBREncryptionPassword {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting EncryptionPasswords..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/encryptionPasswords/export' `
        -Body       @{}

    $outFile = Join-Path $OutputPath "EncryptionPasswords.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

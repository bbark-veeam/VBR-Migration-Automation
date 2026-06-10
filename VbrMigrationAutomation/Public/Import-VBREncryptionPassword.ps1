# Import-VBREncryptionPassword
# Encryption password exports contain metadata only — the actual secret values
# are never included. Automated import is not supported. This function reports
# how many encryption password records are present in the export so the
# operator knows how many to re-enter manually on the target server via the
# Veeam console (Configuration > Encryption Passwords).

function Import-VBREncryptionPassword {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "EncryptionPasswords.json"
    if (-not (Test-Path $inFile)) {
        Write-Host "  No EncryptionPasswords.json found — skipping."
        return
    }

    $payload = Get-Content -Path $inFile -Raw | ConvertFrom-Json -Depth 20
    $count   = @($payload.encryptionPasswords).Count

    if ($count -eq 0) {
        Write-Host "  No encryption passwords in export — skipping."
        return
    }

    Write-Warning "  $count encryption password record(s) found in export. Automated import is not supported — password values are not stored in the export file. Re-enter these passwords manually on the target server via the Veeam console (Configuration > Encryption Passwords)."
}

# Import-VBRCredential
# Imports credentials onto the target VBR server using POST /api/v1/credentials.
# Password values are not stored in the export file (Veeam omits them by
# design), so the user is prompted for each password interactively. The
# source's uniqueId is preserved on each POST so other migrated objects
# (managed servers, repositories, AD domains, protection groups) continue to
# resolve their credentialsId references.

function Import-VBRCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "Credentials.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "Credentials.json not found in $InputPath — skipping."
        return
    }

    $payload     = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    $credentials = @($payload.credentials)

    if ($credentials.Count -eq 0) {
        Write-Host "  No credentials in export — skipping."
        return
    }

    Write-Host "Importing $($credentials.Count) credential(s) from $inFile..."
    Write-Host "  NOTE: Passwords are not stored in exports. You will be prompted for each."

    # Build a set of existing credential uniqueIds on the target so credentials
    # that already exist can be skipped.
    try {
        $existing    = Invoke-RestMethod -Uri "$($Connection.BaseUri)/credentials" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
        $existingIds = @($existing.data | ForEach-Object { $_.uniqueId })
    } catch {
        $existingIds = @()
    }

    foreach ($cred in $credentials) {
        if ($existingIds -contains $cred.uniqueId) {
            Write-Host "  Skipping '$($cred.username)' — uniqueId $($cred.uniqueId) already exists on target."
            continue
        }

        Write-Host "`n  Credential: $($cred.username)  ($($cred.description))"
        $secure = Read-Host -Prompt "    Enter password" -AsSecureString
        $plain  = [System.Net.NetworkCredential]::new('', $secure).Password

        if ([string]::IsNullOrEmpty($plain)) {
            Write-Warning "    Empty password entered — skipping this credential."
            continue
        }

        $body = @{
            type        = $cred.type
            username    = $cred.username
            password    = $plain
            description = $cred.description
            uniqueId    = $cred.uniqueId
        } | ConvertTo-Json

        try {
            $created = Invoke-RestMethod -Uri "$($Connection.BaseUri)/credentials" `
                -Method Post -Headers $Connection.Headers `
                -Body $body -SkipCertificateCheck
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $_.ErrorDetails.Message
            } else {
                $_.Exception.Message
            }
            $details    = Format-RedactedJson -Text $details
            Write-Error "    Failed to create credential (HTTP $statusCode): $details"
            continue
        }

        if ($created.uniqueId -ne $cred.uniqueId) {
            Write-Warning "    Server assigned a different uniqueId ($($created.uniqueId)) than source ($($cred.uniqueId)). Downstream references may break."
        } else {
            Write-Host "    Created with preserved uniqueId: $($created.uniqueId)"
        }
    }

    Write-Host "`n  Credentials import completed."
}

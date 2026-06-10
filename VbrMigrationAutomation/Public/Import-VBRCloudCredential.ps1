# Import-VBRCloudCredential
# Imports cloud credentials onto the target VBR server using
# POST /api/v1/cloudCredentials. Secret values are not stored in the export
# file (Veeam omits them by design), so the user is prompted for each secret
# interactively. The source's uniqueId is preserved on each POST so that
# downstream references (cloud repositories) continue to resolve.
#
# Supported credential types (secret prompted interactively):
#   - Amazon       (accessKey + secretKey)
#   - Google       (accessKey + secretKey)
#   - AzureStorage (account + sharedKey)
#
# Unsupported credential types (warned and skipped — recreate via Veeam console):
#   - AzureCompute (requires app registration / tenant info)
#   - GoogleService (requires service account JSON)

function Import-VBRCloudCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "CloudCredentials.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "CloudCredentials.json not found in $InputPath — skipping."
        return
    }

    $payload = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20

    # Flatten every cloud credential subtype array into a single list.
    $all = [System.Collections.Generic.List[object]]::new()
    foreach ($prop in $payload.PSObject.Properties) {
        foreach ($item in @($prop.Value)) {
            if ($null -ne $item) { $all.Add($item) }
        }
    }

    if ($all.Count -eq 0) {
        Write-Host "  No cloud credentials in export — skipping."
        return
    }

    Write-Host "Importing $($all.Count) cloud credential(s) from $inFile..."
    Write-Host "  NOTE: Secret values are not stored in exports. You will be prompted for each."

    # Build a set of existing cloud credential uniqueIds so duplicates are skipped.
    try {
        $existing    = Invoke-RestMethod -Uri "$($Connection.BaseUri)/cloudCredentials" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
        $existingIds = @($existing.data | ForEach-Object { $_.uniqueId })
    } catch {
        $existingIds = @()
    }

    function Read-Secret {
        param([string] $Prompt)
        $secure = Read-Host -Prompt $Prompt -AsSecureString
        return [System.Net.NetworkCredential]::new('', $secure).Password
    }

    foreach ($cred in $all) {
        if ($existingIds -contains $cred.uniqueId) {
            Write-Host "  Skipping '$($cred.description)' — uniqueId $($cred.uniqueId) already exists on target."
            continue
        }

        Write-Host "`n  Cloud credential ($($cred.type)): $($cred.description)"

        $body = $null
        switch ($cred.type) {
            'Amazon' {
                $secret = Read-Secret "    Enter secret key (accessKey: $($cred.accessKey))"
                if ([string]::IsNullOrEmpty($secret)) { Write-Warning "    Empty — skipping."; continue }
                $body = @{
                    type        = 'Amazon'
                    accessKey   = $cred.accessKey
                    secretKey   = $secret
                    description = $cred.description
                    uniqueId    = $cred.uniqueId
                }
            }
            'Google' {
                $secret = Read-Secret "    Enter HMAC secret (accessKey: $($cred.accessKey))"
                if ([string]::IsNullOrEmpty($secret)) { Write-Warning "    Empty — skipping."; continue }
                $body = @{
                    type        = 'Google'
                    accessKey   = $cred.accessKey
                    secretKey   = $secret
                    description = $cred.description
                    uniqueId    = $cred.uniqueId
                }
            }
            'AzureStorage' {
                $secret = Read-Secret "    Enter shared key (account: $($cred.account))"
                if ([string]::IsNullOrEmpty($secret)) { Write-Warning "    Empty — skipping."; continue }
                $body = @{
                    type        = 'AzureStorage'
                    account     = $cred.account
                    sharedKey   = $secret
                    description = $cred.description
                    uniqueId    = $cred.uniqueId
                }
            }
            'AzureCompute' {
                Write-Warning "    AzureCompute credentials cannot be migrated automatically — requires app registration / tenant info. Recreate manually in the console."
                continue
            }
            'GoogleService' {
                Write-Warning "    GoogleService credentials cannot be migrated automatically — requires service account JSON. Recreate manually in the console."
                continue
            }
            default {
                Write-Warning "    Unknown cloud credential type '$($cred.type)' — skipping."
                continue
            }
        }

        try {
            $created = Invoke-RestMethod -Uri "$($Connection.BaseUri)/cloudCredentials" `
                -Method Post -Headers $Connection.Headers `
                -Body ($body | ConvertTo-Json) -SkipCertificateCheck
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $_.ErrorDetails.Message
            } else {
                $_.Exception.Message
            }
            $details    = Format-RedactedJson -Text $details
            Write-Error "    Failed to create cloud credential (HTTP $statusCode): $details"
            continue
        }

        if ($created.uniqueId -ne $cred.uniqueId) {
            Write-Warning "    Server assigned a different uniqueId ($($created.uniqueId)) than source ($($cred.uniqueId)). Cloud repositories referencing this credential may break."
        } else {
            Write-Host "    Created with preserved uniqueId: $($created.uniqueId)"
        }
    }

    Write-Host "`n  Cloud credentials import completed."
}

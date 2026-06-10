# Import-VBRAgentMigration
# Recreates Veeam Agent protection groups and agent backup jobs on the target
# VBR server. Run after Import-VBRMigration has completed (credentials and
# repositories must exist on the target before agent jobs can be created).
#
# Dependency order:
#   1. Protection Groups   — must exist before jobs; generates UUID mapping file
#   2. Agent Jobs          — UUIDs remapped via the mapping file
#
# Accepts an existing -Connection from a parent caller (e.g.
# Invoke-VBRMigrationImport) to avoid prompting for credentials a second time,
# and -SkipBackupPrompt to avoid duplicate configuration-backup prompts.
#
# Includes a pre-flight check for credentials on the target. If none exist
# (typically because Import-VBRMigration was not run first), the operator is
# given the option to cancel, create a credential interactively, or proceed
# without (expecting downstream failures).

function Import-VBRAgentMigration {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int]                           $Port             = 9419,
        [string]                        $InputPath        = (Join-Path (Get-Location).Path 'output'),
        [PSCustomObject]                $Connection,
        [switch]                        $SkipBackupPrompt,
        [switch]                        $Quiet
    )

    if ($Connection) {
        $conn = $Connection
        Write-Host "Using provided connection (skipping credential prompt)."
    } else {
        $cred = Get-Credential -Message "Enter credentials for $Server"
        $conn = Connect-VBRApi -Server $Server -Port $Port -Credential $cred
    }

    if ($SkipBackupPrompt) {
        Write-Host "Configuration backup step delegated to caller (skipping local prompt)."
    } else {
        $answer = Read-Host "Create a Veeam configuration backup before importing agent objects? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
            Invoke-VBRConfigBackup -Connection $conn
        } else {
            Write-Warning "Skipping configuration backup. Proceed at your own risk."
        }
    }

    # Pre-flight: agent protection groups and AD domains both reference
    # credentialsId. If the target has no credentials configured, the main
    # migration was probably not run first.
    Write-Host "`nChecking target credentials..."
    try {
        $credResponse = Invoke-RestMethod -Uri "$($conn.BaseUri)/credentials" `
            -Method Get -Headers $conn.Headers -SkipCertificateCheck
    } catch {
        throw "Failed to query target credentials: $($_.Exception.Message)"
    }

    $credCount = @($credResponse.data).Count
    if ($credCount -eq 0) {
        Write-Warning "Target VBR server has no credentials configured."
        Write-Host @"
Agent migration requires at least one credential on the target. Choose:
  1) Cancel — run Import-VBRMigration first to migrate credentials, then re-run this.
  2) Create a credential interactively now (POSTs to /api/v1/credentials).
  3) Continue anyway (most agent operations will fail).
"@
        $choice = Read-Host "Enter 1, 2, or 3"

        switch ($choice) {
            '1' { Write-Host "Cancelled. Run Import-VBRMigration first."; return }
            '2' {
                $newCred     = Get-Credential -Message "New credential to create on $Server"
                $description = Read-Host "Description (e.g. 'administrator@DOMAIN.LOCAL')"
                $body        = @{
                    type        = 'Standard'
                    username    = $newCred.UserName
                    password    = $newCred.GetNetworkCredential().Password
                    description = $description
                } | ConvertTo-Json

                try {
                    $created = Invoke-RestMethod -Uri "$($conn.BaseUri)/credentials" `
                        -Method Post -Headers $conn.Headers `
                        -Body $body -SkipCertificateCheck
                    Write-Host "  Created credential id: $($created.uniqueId)"
                } catch {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                    $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                        $_.ErrorDetails.Message
                    } else {
                        $_.Exception.Message
                    }
                    $details    = Format-RedactedJson -Text $details
                    throw "Failed to create credential (HTTP $statusCode): $details"
                }
            }
            '3' { Write-Warning "Continuing without credentials — expect failures." }
            default { throw "Invalid choice. Aborting." }
        }
    } else {
        Write-Host "  Found $credCount credential(s) on target."
    }

    $steps = @(
        'Import-VBRAgentProtectionGroup'
        'Import-VBRAgentJob'
    )

    foreach ($func in $steps) {
        Write-Host "`n--- $func ---"
        try {
            & $func -Connection $conn -InputPath $InputPath -Quiet:$Quiet
        } catch {
            Write-Error "  $func FAILED: $_"
            throw "Agent import halted. Remaining steps were not run."
        }
    }

    Write-Host "`nAgent import complete."
}

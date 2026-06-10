# Invoke-VBRMigrationExport
# Single-command wrapper that runs Export-VBRMigration followed by
# Export-VBRAgentMigration against the same source server. Authenticates once
# and passes the resulting connection through to both phases so the operator
# is prompted for credentials only one time.
#
# If the main export fails, the agent export is not attempted.

function Invoke-VBRMigrationExport {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int]                           $Port       = 9419,
        [string]                        $OutputPath = (Join-Path (Get-Location).Path 'output')
    )

    $cred = Get-Credential -Message "Enter credentials for $Server"
    $conn = Connect-VBRApi -Server $Server -Port $Port -Credential $cred

    Write-Host "`n========================================="
    Write-Host "Phase 1 of 2: Main export (Export-VBRMigration)"
    Write-Host "=========================================`n"

    try {
        Export-VBRMigration -Server $Server -Port $Port -OutputPath $OutputPath -Connection $conn
    } catch {
        Write-Error "Main export failed: $_. Halting before agent export."
        throw
    }

    Write-Host "`n========================================="
    Write-Host "Phase 2 of 2: Agent export (Export-VBRAgentMigration)"
    Write-Host "=========================================`n"

    try {
        Export-VBRAgentMigration -Server $Server -Port $Port -OutputPath $OutputPath -Connection $conn
    } catch {
        Write-Error "Agent export failed: $_"
        throw
    }

    Write-Host "`n========================================="
    Write-Host "Full export complete (main + agents)."
    Write-Host "Artefacts: $OutputPath"
    Write-Host "========================================="
}

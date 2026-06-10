# Export-VBRAgentMigration
# Orchestrates the Veeam Agent export: exports protection groups and agent
# backup jobs from the source VBR server, writing each to the output directory.
# Run before Import-VBRAgentMigration on the target side.
#
# Accepts an existing -Connection from a parent caller (e.g.
# Invoke-VBRMigrationExport) to avoid prompting for credentials a second time.

function Export-VBRAgentMigration {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int]                           $Port       = 9419,
        [string]                        $OutputPath = (Join-Path (Get-Location).Path 'output'),
        [PSCustomObject]                $Connection
    )

    if ($Connection) {
        $conn = $Connection
        Write-Host "Using provided connection (skipping credential prompt)."
    } else {
        $cred = Get-Credential -Message "Enter credentials for $Server"
        $conn = Connect-VBRApi -Server $Server -Port $Port -Credential $cred
    }

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $steps = @(
        'Export-VBRAgentProtectionGroup'
        'Export-VBRAgentJob'
    )

    $failed = [System.Collections.Generic.List[string]]::new()

    foreach ($func in $steps) {
        Write-Host "`n--- $func ---"
        try {
            & $func -Connection $conn -OutputPath $OutputPath
        } catch {
            Write-Error "  $func FAILED: $_"
            $failed.Add($func)
        }
    }

    Write-Host "`n========================================="
    if ($failed.Count -eq 0) {
        Write-Host "Agent export complete. Artefacts written to: $OutputPath"
    } else {
        Write-Warning "Agent export finished with $($failed.Count) failure(s):"
        $failed | ForEach-Object { Write-Warning "  - $_" }
    }
}

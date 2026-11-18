# Import-VBRManagedServer
# Imports managed-server records onto the target VBR server via the Automation
# API. The Automation API does not handle duplicate names gracefully (it
# errors), so the target is queried first and any managed servers already
# present are stripped from the import payload before submission.

function Import-VBRManagedServer {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "ManagedServers.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "ManagedServers.json not found in $InputPath — skipping."
        return
    }

    $payload = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    $count   = @($payload.windowsHosts).Count + @($payload.linuxHosts).Count +
               @($payload.viHosts).Count + @($payload.cloudDirectorHosts).Count
    if ($count -eq 0) {
        Write-Host "  No managed servers in export — skipping."
        return
    }

    try {
        $existing      = Invoke-RestMethod -Uri "$($Connection.BaseUri)/backupInfrastructure/managedServers" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
        $existingNames = @($existing.data | ForEach-Object { $_.name })
    } catch {
        Write-Warning "  Could not query existing managed servers — skip-if-exists check disabled: $($_.Exception.Message)"
        $existingNames = @()
    }

    $totalSkipped = 0
    foreach ($category in @('windowsHosts', 'linuxHosts', 'viHosts', 'cloudDirectorHosts')) {
        $original = @($payload.$category)
        if ($original.Count -eq 0) { continue }

        $kept    = @($original | Where-Object { $_.name -notin $existingNames })
        $skipped = $original.Count - $kept.Count
        if ($skipped -gt 0) {
            Write-Host "  Skipping $skipped $category already present on target."
            $payload.$category = $kept
            $totalSkipped += $skipped
        }
    }

    $remaining = @($payload.windowsHosts).Count + @($payload.linuxHosts).Count +
                 @($payload.viHosts).Count + @($payload.cloudDirectorHosts).Count
    if ($remaining -eq 0) {
        Write-Host "  All managed servers already exist on target — nothing to import."
        return
    }

    Resolve-VBRVsaWindowsCredential -Connection $Connection -Payload $payload

    Write-Host "Importing ManagedServers from $inFile (importing $remaining, skipped $totalSkipped)..."

    $rawJson = $payload | ConvertTo-Json -Depth 20

    Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/managedServers/import' `
        -Body       $rawJson `
        -Quiet:$Quiet

    Write-Host "  ManagedServers import completed."
}

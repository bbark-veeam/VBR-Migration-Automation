# Test-VBRPairedApplianceHost
# Finds Linux managed servers in an export that were added by certificate
# pairing (Veeam Infrastructure Appliance, e.g. a hardened repository). Their
# export has no credentials and no SSH fingerprint, which the Automation import
# rejects, so each must be paired with the target from its Host Management
# Console before the import runs.
#
# Runs before anything is imported. If any such host is missing from the
# target, it lists them and waits: the operator pairs them, then presses Enter
# to re-check, or types Q to abort. The import continues only once every
# appliance is on the target. A host present under a name that differs only in
# case is accepted with a warning, because repositories reference their host
# by name.

function Test-VBRPairedApplianceHost {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $TargetVBR
    )

    $paired = @(Get-VBRPairedApplianceHost -InputPath $InputPath)
    if ($paired.Count -eq 0) {
        Write-Host "  None in the export."
        return
    }

    $target = if ($TargetVBR) { $TargetVBR } else { 'the target VBR' }

    while ($true) {
        $missing = @(Get-VBRMissingApplianceHost -Connection $Connection -Hosts $paired)
        if ($missing.Count -eq 0) {
            Write-Host "  Certificate-paired appliances on the target: $(($paired | ForEach-Object Name) -join ', ')"
            return
        }

        Write-Host "  These Linux hosts are certificate-paired appliances (no credentials or SSH fingerprint in the export)"
        Write-Host "  and are not on $($target):"
        foreach ($h in $missing) {
            $usedBy = if ($h.Repositories.Count -gt 0) { "  (used by repository: $($h.Repositories -join ', '))" } else { '' }
            Write-Host "    - $($h.Name)$usedBy"
        }
        Write-Host "  They can't be imported. Pair each one with $target from its Host Management Console,"
        Write-Host "  using exactly the name shown above. An appliance pairs with one VBR at a time, so this"
        Write-Host "  removes it from the source. Nothing has been imported yet."

        $answer = Read-Host "Press Enter once paired to re-check, or type Q to abort the import"
        if ($answer -match '^[Qq]') {
            throw "Import aborted: certificate-paired appliances not on the target ($(($missing | ForEach-Object Name) -join ', ')). Nothing has been imported."
        }
    }
}

function Get-VBRMissingApplianceHost {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [object[]]       $Hosts
    )

    $targetNames = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/managedServers' |
                     Where-Object { $_.name } | ForEach-Object { [string]$_.name })

    foreach ($h in $Hosts) {
        if ($targetNames | Where-Object { $_ -ceq $h.Name }) { continue }

        $caseOnly = $targetNames | Where-Object { $_ -ieq $h.Name } | Select-Object -First 1
        if ($caseOnly) {
            Write-Warning "  Appliance '$($h.Name)' is on the target as '$caseOnly' (case differs). Repositories that reference it by name may fail to import."
            continue
        }
        $h
    }
}

function Get-VBRPairedApplianceHost {
    param([Parameter(Mandatory)] [string] $InputPath)

    $mgrFile = Join-Path $InputPath 'ManagedServers.json'
    if (-not (Test-Path $mgrFile)) { return }
    $mgr = Get-Content $mgrFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20

    $repos = @()
    $repoFile = Join-Path $InputPath 'Repositories.json'
    if (Test-Path $repoFile) {
        $repoData = Get-Content $repoFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        $repos = @($repoData.PSObject.Properties | ForEach-Object { @($_.Value) } | Where-Object { $_ })
    }

    foreach ($h in @($mgr.linuxHosts)) {
        if (-not $h -or -not $h.name) { continue }
        $hasCredentials = $h.credentials -and ($h.credentials.credentialsTag -or $h.credentials.credentialsName)
        $hasFingerprint = -not [string]::IsNullOrWhiteSpace([string]$h.sshFingerprint)
        if ($hasCredentials -or $hasFingerprint) { continue }

        [pscustomobject]@{
            Name         = [string]$h.name
            Repositories = @($repos | Where-Object { $_.hostName -ieq $h.name } | ForEach-Object { [string]$_.name })
        }
    }
}

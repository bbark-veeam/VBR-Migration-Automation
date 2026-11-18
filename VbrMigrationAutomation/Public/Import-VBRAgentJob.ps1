# Import-VBRAgentJob
# Recreates Veeam Agent backup jobs on the target VBR server.
# Requires AgentProtectionGroupMap.json (written by Import-VBRAgentProtectionGroup).
#
# Computer references in agent jobs (`computers[]`, `guestProcessing
# .appAwareProcessing.appSettings[].machineObject`, `guestProcessing
# .guestFSIndexing.indexingSettings[].machineObject`) reference per-server
# discovered-entity IDs that don't exist on the target until the protection
# group's rescan completes. This function:
#   1. Identifies the target protection groups it needs entity data for
#   2. Triggers a rescan on each and waits for completion
#   3. Queries each protection group's discoveredEntities to build a
#      name -> entity-id map
#   4. Substitutes computer-level IDs everywhere they appear in the job body
#   5. Maps each backupRepositoryId to the same-named repository's ID on the target
#
# Re-runs are safe: jobs already on the target (matched by name) are skipped.

function Import-VBRAgentJob {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [switch]                                $Quiet
    )

    $inFile  = Join-Path $InputPath "AgentJobs.json"
    $mapFile = Join-Path $InputPath "AgentProtectionGroupMap.json"

    if (-not (Test-Path $inFile)) {
        Write-Warning "AgentJobs.json not found in $InputPath — skipping."
        return
    }
    if (-not (Test-Path $mapFile)) {
        throw "AgentProtectionGroupMap.json not found in $InputPath. Run Import-VBRAgentProtectionGroup first."
    }

    $jobs = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    if (@($jobs).Count -eq 0) {
        Write-Host "  No agent jobs in export — skipping."
        return
    }

    # pgMap: source protection-group uniqueId -> target protection-group id
    $pgMap = @{}
    Get-Content -Path $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 5 |
        ForEach-Object { $pgMap[$_.sourceId] = $_.targetId }

    # Build the set of job names already present on the target.
    $existingJobNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    try {
        $skip = 0; $limit = 100
        do {
            $resp = Invoke-RestMethod -Uri "$($Connection.BaseUri)/jobs?skip=$skip&limit=$limit" `
                -Method Get -Headers $Connection.Headers -SkipCertificateCheck
            foreach ($j in @($resp.data)) {
                if ($j.name) { $existingJobNames.Add($j.name) | Out-Null }
            }
            $skip += $limit
        } while ($existingJobNames.Count -lt $resp.pagination.total)
    } catch {
        Write-Warning "  Could not query existing jobs — skip-if-exists check disabled: $($_.Exception.Message)"
    }

    # Collect the set of target protection groups that need discovered-entity
    # data. Only protection groups referenced by computer-level targets
    # (WindowsComputer / LinuxComputer) in jobs that will actually be created
    # need this lookup; jobs targeting whole protection groups don't.
    $pgsNeedingDiscovery = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($job in $jobs) {
        if ($existingJobNames.Contains($job.name)) { continue }
        foreach ($c in @($job.computers)) {
            if ($c.type -in @('WindowsComputer', 'LinuxComputer') -and
                $c.protectionGroupId -and $pgMap.ContainsKey($c.protectionGroupId)) {
                $null = $pgsNeedingDiscovery.Add($pgMap[$c.protectionGroupId])
            }
        }
    }

    # For each protection group, trigger a rescan, wait for completion, then
    # fetch entities. $entitiesByPg[targetPgId] = @{ 'host.fqdn.tld' = entityId }
    $entitiesByPg = @{}

    if ($pgsNeedingDiscovery.Count -gt 0) {
        Write-Host "  Refreshing discovered entities for $($pgsNeedingDiscovery.Count) protection group(s)..."
    }

    foreach ($targetPgId in $pgsNeedingDiscovery) {
        Write-Host "    Protection group $targetPgId — triggering rescan..."

        try {
            Invoke-AutomationSession `
                -Connection $Connection `
                -Endpoint   "/agents/protectionGroups/$targetPgId/rescan" `
                -Body       @{} `
                -Quiet:$Quiet | Out-Null
        } catch {
            Write-Warning "    Rescan failed for protection group $targetPgId : $($_.Exception.Message)"
            Write-Warning "    Continuing to query discovered entities anyway in case they're already populated."
        }

        try {
            $entitiesResp = Invoke-RestMethod `
                -Uri "$($Connection.BaseUri)/agents/protectionGroups/$targetPgId/discoveredEntities" `
                -Method Get -Headers $Connection.Headers -SkipCertificateCheck
        } catch {
            Write-Warning "    Could not query discovered entities for protection group $targetPgId : $($_.Exception.Message)"
            $entitiesByPg[$targetPgId] = @{}
            continue
        }

        $entityMap = @{}
        foreach ($e in @($entitiesResp.data)) {
            if ($e.name -and $e.id) {
                $entityMap[$e.name.ToLower()] = $e.id
            }
        }
        $entitiesByPg[$targetPgId] = $entityMap
        Write-Host "      Found $($entityMap.Count) discovered entity/ies."
    }

    # Helper: remap a computer-like reference object (used in three places per
    # job body). Mutates the object in place. Returns $true if remap succeeded,
    # $false if a required lookup failed (caller skips the job in that case).
    function Update-ComputerReference {
        param([Parameter(Mandatory)] $Computer)

        if (-not $Computer.protectionGroupId) { return $true }
        if (-not $pgMap.ContainsKey($Computer.protectionGroupId)) { return $true }

        $newPgId = $pgMap[$Computer.protectionGroupId]
        $Computer.protectionGroupId = $newPgId

        if ($Computer.parentObjectId -and $pgMap.ContainsKey($Computer.parentObjectId)) {
            $Computer.parentObjectId = $pgMap[$Computer.parentObjectId]
        }

        if ($Computer.type -eq 'ProtectionGroup') {
            $Computer.id = $newPgId
            return $true
        }

        if ($Computer.type -in @('WindowsComputer', 'LinuxComputer')) {
            $entityMap = $entitiesByPg[$newPgId]
            if (-not $entityMap -or -not $Computer.name) {
                Write-Warning "    Cannot resolve discovered entity for '$($Computer.name)' (no entity map for PG $newPgId)."
                return $false
            }
            $key = $Computer.name.ToLower()
            if ($entityMap.ContainsKey($key)) {
                $Computer.id = $entityMap[$key]
                return $true
            }
            Write-Warning "    Cannot find discovered entity '$($Computer.name)' in target PG $newPgId. Available: $($entityMap.Keys -join ', ')"
            return $false
        }

        return $true
    }

    $targetRepos = @()
    try {
        $targetRepos = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/repositories')
    } catch {
        Write-Warning "  Could not list target repositories — repository references can't be checked: $($_.Exception.Message)"
    }
    try {
        $targetRepos += @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/scaleOutRepositories')
    } catch { }
    $repoResolver = New-VBRRepositoryIdResolver -InputPath $InputPath -TargetRepositories $targetRepos

    Write-Host "Importing Agent Jobs..."

    $created      = 0
    $skippedCount = 0
    $failedCount  = 0

    foreach ($job in $jobs) {
        if ($existingJobNames.Contains($job.name)) {
            Write-Host "  Skipping '$($job.name)' — already exists on target."
            $skippedCount++
            continue
        }

        $allResolved = $true

        # Remap every place a computer reference appears in the job body.
        foreach ($computer in @($job.computers)) {
            if (-not (Update-ComputerReference -Computer $computer)) { $allResolved = $false }
        }

        if ($job.guestProcessing.appAwareProcessing.appSettings) {
            foreach ($app in @($job.guestProcessing.appAwareProcessing.appSettings)) {
                if ($app.machineObject) {
                    if (-not (Update-ComputerReference -Computer $app.machineObject)) { $allResolved = $false }
                }
            }
        }

        if ($job.guestProcessing.guestFSIndexing.indexingSettings) {
            foreach ($idx in @($job.guestProcessing.guestFSIndexing.indexingSettings)) {
                if ($idx.machineObject) {
                    if (-not (Update-ComputerReference -Computer $idx.machineObject)) { $allResolved = $false }
                }
            }
        }

        $badRepos = @(Update-VBRJobRepositoryId -Job $job -Resolver $repoResolver)
        foreach ($r in $badRepos) {
            Write-Warning "  Job '$($job.name)': backup repository $r is not on the target."
            $allResolved = $false
        }

        if (-not $allResolved) {
            Write-Warning "  Skipping job '$($job.name)' — one or more computer or repository references could not be resolved on the target. See warnings above."
            $failedCount++
            continue
        }

        # Strip read-only fields before POST.
        $body = $job | Select-Object -Property * -ExcludeProperty id, isDisabled

        $result = Invoke-AutomationSession `
            -Connection $Connection `
            -Endpoint   '/jobs' `
            -Body       $body `
            -Quiet:$Quiet

        Write-Host "  Created job '$($job.name)' — id: $($result.id)"
        $created++
    }

    Write-Host "  Agent Jobs import completed ($created created, $skippedCount skipped, $failedCount unresolved)."
}

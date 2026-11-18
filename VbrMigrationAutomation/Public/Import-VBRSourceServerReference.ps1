# Import-VBRSourceServerReference
# Repositories may reference the Source Veeam Server itself (or other hosts
# not present in ManagedServers.json) by hostname and/or managedServerId UUID.
# Without those host records on the target, repository import fails validation.
#
# This function:
#   1. Parses Repositories.json for unique host / UUID references
#   2. Compares against ManagedServers.json (already-imported hosts)
#   3. For each missing host, prompts the user for OS type and a credential
#      (selected from imported credentials on the target)
#   4. POSTs a single-entry ManagedServers payload via the Automation API,
#      preserving the source's UUID so repository cross-references resolve
#
# Only repositories that will actually be imported count: ones whose name is
# already on the target are skipped by Import-VBRRepository, and mount servers
# on the Source Veeam Server are remapped to the target VBR there.
#
# When -IsVSA is set, the source VBR itself is excluded from the auto-add
# list — VSAs cannot be added as managed servers in another Veeam install.
# Adding a Windows source VBR warns that its local console will no longer
# connect to it (the web console and remote consoles still do).

function Import-VBRSourceServerReference {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $repoFile = Join-Path $InputPath "Repositories.json"
    $mgrFile  = Join-Path $InputPath "ManagedServers.json"

    if (-not (Test-Path $repoFile)) {
        Write-Host "  No Repositories.json — nothing to check."
        return
    }

    $repos = Get-Content $repoFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20

    # Build set of already-imported hostnames from ManagedServers.json.
    $existingHosts = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path $mgrFile) {
        $mgr = Get-Content $mgrFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        foreach ($category in @('windowsHosts', 'linuxHosts', 'viHosts', 'cloudDirectorHosts')) {
            foreach ($entry in @($mgr.$category)) {
                if ($entry.name) { $existingHosts.Add($entry.name) | Out-Null }
            }
        }
    }

    # Map: hostname -> [pscustomobject]@{ ManagedServerId; OsHint }
    $hostRefs = @{}

    function Add-HostRef {
        param([string] $HostName, [string] $ManagedServerId, [string] $OsHint)
        if ([string]::IsNullOrWhiteSpace($HostName)) { return }
        if (-not $hostRefs.ContainsKey($HostName)) {
            $hostRefs[$HostName] = [pscustomobject]@{
                ManagedServerId = $ManagedServerId
                OsHint          = $OsHint
            }
        } else {
            if (-not $hostRefs[$HostName].ManagedServerId -and $ManagedServerId) {
                $hostRefs[$HostName].ManagedServerId = $ManagedServerId
            }
            if (-not $hostRefs[$HostName].OsHint -and $OsHint) {
                $hostRefs[$HostName].OsHint = $OsHint
            }
        }
    }

    # Repositories whose name is already on the target are skipped by
    # Import-VBRRepository, so their hosts are not needed.
    $targetRepoNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($r in (Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/repositories')) {
            if ($r.name) { $targetRepoNames.Add([string]$r.name) | Out-Null }
        }
    } catch {
        Write-Warning "  Could not list target repositories — every exported repository is treated as to be imported: $($_.Exception.Message)"
    }

    foreach ($category in $repos.PSObject.Properties) {
        foreach ($repo in @($category.Value)) {
            if (-not $repo) { continue }
            if ($repo.name -and $targetRepoNames.Contains([string]$repo.name)) { continue }

            if ($repo.hostName) {
                $osHint = if ($category.Name -match 'Linux') { 'Linux' }
                          elseif ($category.Name -match 'Windows') { 'Windows' }
                          else { '' }
                Add-HostRef -HostName $repo.hostName -OsHint $osHint
            }
            # A mount server on the Source Veeam Server is remapped to the
            # target VBR by Import-VBRRepository, so it doesn't need the source.
            $linuxMount   = [string]$repo.mountServer.linux.mountServerName
            $windowsMount = [string]$repo.mountServer.windows.mountServerName
            if ($linuxMount -and $linuxMount -ine $SourceVBR) {
                Add-HostRef -HostName $linuxMount -OsHint 'Linux'
            }
            if ($windowsMount -and $windowsMount -ine $SourceVBR) {
                Add-HostRef -HostName $windowsMount -OsHint 'Windows'
            }
            if ($repo.proxyAppliance.managedServerId -and $repo.hostName) {
                Add-HostRef -HostName $repo.hostName -ManagedServerId $repo.proxyAppliance.managedServerId
            }
        }
    }

    $missing = @($hostRefs.Keys | Where-Object { -not $existingHosts.Contains($_) })

    if ($IsVSA -and $SourceVBR) {
        $skipped = @($missing | Where-Object { $_ -ieq $SourceVBR })
        if ($skipped.Count -gt 0) {
            Write-Host "  Skipping '$SourceVBR' — source is a VSA and cannot be added as a managed server. References will be remapped to target VBR by Import-VBRRepository."
            $missing = @($missing | Where-Object { $_ -ine $SourceVBR })
        }
    }

    if ($missing.Count -gt 0) {
        try {
            $onTarget = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/managedServers' |
                          Where-Object { $_.name } | ForEach-Object { [string]$_.name })
        } catch {
            throw "Failed to query target managed servers: $($_.Exception.Message)"
        }
        $already = @($missing | Where-Object { $m = $_; $onTarget | Where-Object { $_ -ieq $m } })
        foreach ($h in $already) { Write-Host "  Skipping '$h' — already a managed server on the target." }
        $missing = @($missing | Where-Object { $already -notcontains $_ })
    }

    if ($missing.Count -eq 0) {
        Write-Host "  No additional hosts to add — repository host references will be satisfied by remap or already exist."
        return
    }

    Write-Host "  Found $($missing.Count) host(s) referenced by repositories but not in ManagedServers.json:"
    foreach ($h in $missing) { Write-Host "    - $h" }
    Write-Host "  These will be added as managed servers on the target so repository imports validate."

    if ($SourceVBR -and ($missing | Where-Object { $_ -ieq $SourceVBR })) {
        $hosted = @($repos.PSObject.Properties | ForEach-Object { @($_.Value) } |
                    Where-Object { $_ -and $_.hostName -ieq $SourceVBR -and -not $targetRepoNames.Contains([string]$_.name) } |
                    ForEach-Object { $_.name })
        Write-Warning "  '$SourceVBR' (the Source Veeam Server) hosts repositories being imported: $($hosted -join ', ')."
        Write-Warning "  Once it is a managed server of the target, its local console can no longer connect to it."
        Write-Warning "  The web console and remote consoles still work; reinstalling the console on the source is expected to restore it."
    }

    try {
        $targetCreds = [pscustomobject]@{ data = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/credentials') }
    } catch {
        throw "Failed to query target credentials: $($_.Exception.Message)"
    }
    $credList = @($targetCreds.data)
    $targetIsVsa = (Get-VBRServerPlatform -Connection $Connection) -eq 'Linux'

    $payload = [ordered]@{
        windowsHosts       = @()
        linuxHosts         = @()
        viHosts            = @()
        cloudDirectorHosts = @()
    }

    foreach ($hostName in $missing) {
        $info = $hostRefs[$hostName]

        Write-Host "`n  Host: $hostName"

        $osType = $info.OsHint
        while ($osType -notin @('Windows', 'Linux')) {
            $osType = Read-Host "    OS type (Windows / Linux)"
        }

        if ($targetIsVsa -and $osType -eq 'Windows') {
            $cred = Select-VBRVsaCredential -Connection $Connection -HostName $hostName `
                -Reason "Target is a VSA: Windows servers need an FQDN\user or UPN credential."
        } else {
            Write-Host "    Imported credentials on target:"
            for ($i = 0; $i -lt $credList.Count; $i++) {
                Write-Host "      [$($i + 1)] $($credList[$i].username) — $($credList[$i].description)  ($($credList[$i].uniqueId))"
            }
            $choice = $null
            while (-not ($choice -as [int]) -or $choice -lt 1 -or $choice -gt $credList.Count) {
                $choice = Read-Host "    Select credential by number"
            }
            $cred = $credList[[int]$choice - 1]
        }

        $entry = [ordered]@{
            type        = if ($osType -eq 'Linux') { 'LinuxHost' } else { 'WindowsHost' }
            name        = $hostName
            description = "Auto-added during migration to satisfy repository host references."
            credentials = [ordered]@{
                credentialsName = $cred.username
                credentialsTag  = $cred.uniqueId
            }
        }

        if ($info.ManagedServerId) {
            $entry['uniqueId'] = $info.ManagedServerId
        }

        if ($osType -eq 'Linux') {
            $payload.linuxHosts += $entry
        } else {
            $payload.windowsHosts += $entry
        }
    }

    Write-Host "`n  Adding $($missing.Count) managed server(s) via Automation API..."

    Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/managedServers/import' `
        -Body       $payload `
        -Quiet:$Quiet | Out-Null

    Write-Host "  Source server reference import completed."
}

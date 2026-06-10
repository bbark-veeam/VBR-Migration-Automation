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
# When -IsVSA is set, the source VBR itself is excluded from the auto-add
# list — VSAs cannot be added as managed servers in another Veeam install.
# Auto-added entries are documented in the README as objects to remove after
# the migration has been validated.

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

    foreach ($category in $repos.PSObject.Properties) {
        foreach ($repo in @($category.Value)) {
            if ($repo.hostName) {
                $osHint = if ($category.Name -match 'Linux') { 'Linux' }
                          elseif ($category.Name -match 'Windows') { 'Windows' }
                          else { '' }
                Add-HostRef -HostName $repo.hostName -OsHint $osHint
            }
            if ($repo.mountServer.linux.mountServerName) {
                Add-HostRef -HostName $repo.mountServer.linux.mountServerName -OsHint 'Linux'
            }
            if ($repo.mountServer.windows.mountServerName) {
                Add-HostRef -HostName $repo.mountServer.windows.mountServerName -OsHint 'Windows'
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

    if ($missing.Count -eq 0) {
        Write-Host "  No additional hosts to add — repository host references will be satisfied by remap or already exist."
        return
    }

    Write-Host "  Found $($missing.Count) host(s) referenced by repositories but not in ManagedServers.json:"
    foreach ($h in $missing) { Write-Host "    - $h" }
    Write-Host "  These will be added as managed servers on the target so repository imports validate."
    Write-Host "  Per the README, remove them after migration validation completes."

    try {
        $targetCreds = Invoke-RestMethod -Uri "$($Connection.BaseUri)/credentials" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
    } catch {
        throw "Failed to query target credentials: $($_.Exception.Message)"
    }
    $credList = @($targetCreds.data)

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

        Write-Host "    Imported credentials on target:"
        for ($i = 0; $i -lt $credList.Count; $i++) {
            Write-Host "      [$($i + 1)] $($credList[$i].username) — $($credList[$i].description)  ($($credList[$i].uniqueId))"
        }
        $choice = $null
        while (-not ($choice -as [int]) -or $choice -lt 1 -or $choice -gt $credList.Count) {
            $choice = Read-Host "    Select credential by number"
        }
        $cred = $credList[[int]$choice - 1]

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

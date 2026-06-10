# Import-VBRProxy
# Imports backup proxies onto the target VBR server. Two filters run before
# import:
#   1. Proxies whose host is not registered as a managed server on the target
#      are dropped — typically the source VBR's auto-provisioned default
#      VMware Backup Proxy, which the target has its own equivalent of.
#   2. Proxies whose host already has a proxy registered on the target are
#      dropped (idempotency on re-runs).

function Import-VBRProxy {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "Proxies.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "Proxies.json not found in $InputPath — skipping."
        return
    }

    $payload = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    $proxies = @($payload.proxies)

    if ($proxies.Count -eq 0) {
        Write-Host "  No proxies in export — skipping."
        return
    }

    # Build the set of host names registered as managed servers on the target.
    $knownHosts = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    try {
        $targetServers = Invoke-RestMethod `
            -Uri "$($Connection.BaseUri)/backupInfrastructure/managedServers" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
        foreach ($s in @($targetServers.data)) {
            if ($s.name) { $knownHosts.Add($s.name) | Out-Null }
        }
    } catch {
        Write-Warning "  Could not query target managed servers — proxy filter disabled: $($_.Exception.Message)"
    }

    # Build the set of host names that already have a proxy on the target.
    $existingProxyHosts = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    try {
        $targetProxies = Invoke-RestMethod `
            -Uri "$($Connection.BaseUri)/backupInfrastructure/proxies" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
        foreach ($p in @($targetProxies.data)) {
            if ($p.server.hostName) { $existingProxyHosts.Add($p.server.hostName) | Out-Null }
        }
    } catch {
        Write-Warning "  Could not query existing proxies — skip-if-exists check disabled: $($_.Exception.Message)"
    }

    $kept    = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()

    foreach ($proxy in $proxies) {
        $proxyHost = $proxy.server.hostName

        if ([string]::IsNullOrWhiteSpace($proxyHost) -or -not $knownHosts.Contains($proxyHost)) {
            $reason = if ([string]::IsNullOrWhiteSpace($proxyHost)) { "no host name" } else { "host '$proxyHost' not in target's managed servers" }
            $skipped.Add("$($proxy.type) — $reason")
            continue
        }

        if ($existingProxyHosts.Contains($proxyHost)) {
            $skipped.Add("$($proxy.type) on '$proxyHost' — already exists on target")
            continue
        }

        $kept.Add($proxy)
    }

    if ($skipped.Count -gt 0) {
        Write-Warning "  Skipping $($skipped.Count) proxy/ies whose host is not on the target:"
        foreach ($s in $skipped) { Write-Warning "    - $s" }
        Write-Host "  These are typically source-VBR-bound (e.g. the default VMware Backup Proxy on the source). The target VBR has its own equivalent installed by default."
    }

    if ($kept.Count -eq 0) {
        Write-Host "  No remaining proxies to import — skipping."
        return
    }

    $payload.proxies = $kept.ToArray()
    $rawJson = $payload | ConvertTo-Json -Depth 20

    Write-Host "Importing $($kept.Count) proxy/ies from $inFile..."

    Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/proxies/import' `
        -Body       $rawJson `
        -Quiet:$Quiet

    Write-Host "  Proxies import completed."
}

# Test-VBRVsaWindowsCredential
# A Veeam Software Appliance (Linux VBR) can only add Windows servers with a
# credential in FQDN\user or UPN (user@fqdn) form; NETBIOS\user, HOST\user and
# bare user names fail ("Failed to discover server packages").
#
# Helpers:
#   Get-VBRServerPlatform        - the target's platform from /serverInfo, cached on the connection
#   Test-VBRVsaCredentialFormat  - whether a user name is in a form a VSA accepts
#   Test-VBRVsaWindowsCredential - pre-check: on a VSA target, if a Windows host
#                                  needs a different credential and none in an
#                                  accepted form exists, offer to add one now, wait
#                                  while it is added on the VSA, or abort, before
#                                  anything is imported
#   New-VBRVsaCredential         - prompt for and create an accepted credential
#   Resolve-VBRVsaWindowsCredential - at the managed-server step, prompt for an
#                                  accepted credential for each such host
#   Select-VBRVsaCredential      - per-host picker: an existing accepted credential,
#                                  a new one created now, one added on the VSA, or abort

function Get-VBRServerPlatform {
    param([Parameter(Mandatory)] [PSCustomObject] $Connection)

    if ($Connection.PSObject.Properties['ServerPlatform']) { return $Connection.ServerPlatform }

    $info = Invoke-RestMethod -Uri "$($Connection.BaseUri)/serverInfo" -Method Get `
        -Headers $Connection.Headers -SkipCertificateCheck
    $platform = [string]$info.platform
    $Connection | Add-Member -NotePropertyName ServerPlatform -NotePropertyValue $platform -Force
    return $platform
}

function Test-VBRVsaCredentialFormat {
    param([AllowEmptyString()] [string] $UserName)

    if ($UserName -match '^[^\\@\s]+@[^\\@\s]+\.[^\\@\s]+$') { return $true }
    if ($UserName -match '^[^\\@\s]+\.[^\\@\s]+\\[^\\@\s]+$') { return $true }
    return $false
}

function Test-VBRVsaWindowsCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath
    )

    if ((Get-VBRServerPlatform -Connection $Connection) -ne 'Linux') {
        Write-Host "  Target is not a VSA — Windows credential formats not restricted."
        return
    }

    $hosts = @(Get-VBRVsaInvalidWindowsHost -InputPath $InputPath)
    if ($hosts.Count -gt 0) {
        $onTarget = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/managedServers' |
                      Where-Object { $_.name } | ForEach-Object { [string]$_.name })
        $hosts = @($hosts | Where-Object { $n = $_.name; -not ($onTarget | Where-Object { $_ -ieq $n }) })
    }
    if ($hosts.Count -eq 0) {
        Write-Host "  Target is a VSA; Windows hosts to import use FQDN\user or UPN credentials (or are already on the target)."
        return
    }

    Write-Host "  Target is a VSA. It can only add Windows servers with FQDN\user or UPN (user@fqdn) credentials."
    Write-Host "  These Windows hosts use another form and will need a different credential:"
    foreach ($h in $hosts) { Write-Host "    - $($h.name)  ($($h.credentials.credentialsName))" }

    while (@(Get-VBRVsaCredentialCandidate -Connection $Connection -InputPath $InputPath).Count -eq 0) {
        Write-Host "  No credential in FQDN\user or UPN form exists in the export or on the target. Nothing has been imported yet."
        Write-Host "    [1] Add a credential now"
        Write-Host "    [2] Add it manually on the VSA, then re-check"
        Write-Host "    [Q] Abort the import"
        $answer = Read-Host "  Choose 1, 2 or Q"

        switch -Regex ($answer) {
            '^1$'    { New-VBRVsaCredential -Connection $Connection | Out-Null }
            '^2$'    { Read-Host "  Add the credential in the VSA console (Credentials and Passwords), then press Enter to re-check" | Out-Null }
            '^[Qq]$' { throw "Import aborted: no FQDN\user or UPN credential for the Windows hosts on the VSA target. Nothing has been imported." }
        }
    }
    Write-Host "  You will be asked to choose a credential for each one when managed servers are imported."
}

function New-VBRVsaCredential {
    param([Parameter(Mandatory)] [PSCustomObject] $Connection)

    $userName = $null
    while (-not $userName) {
        $entered = Read-Host "  User name (user@domain.fqdn or domain.fqdn\user), blank to go back"
        if ([string]::IsNullOrWhiteSpace($entered)) { return $null }
        if (Test-VBRVsaCredentialFormat $entered.Trim()) {
            $userName = $entered.Trim()
        } else {
            Write-Host "  '$entered' is not in FQDN\user or UPN form."
        }
    }

    $secure = Read-Host -Prompt "  Password for $userName" -AsSecureString
    $plain  = [System.Net.NetworkCredential]::new('', $secure).Password
    if ([string]::IsNullOrEmpty($plain)) {
        Write-Host "  Empty password — credential not created."
        return $null
    }

    $body = @{
        type        = 'Standard'
        username    = $userName
        password    = $plain
        description = 'Added during migration for Windows hosts on a VSA target'
    } | ConvertTo-Json
    $plain = $null

    try {
        $created = Invoke-RestMethod -Uri "$($Connection.BaseUri)/credentials" -Method Post `
            -Headers $Connection.Headers -Body $body -SkipCertificateCheck
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Host "  Failed to create credential (HTTP $statusCode): $(Format-RedactedJson -Text $details)"
        return $null
    } finally {
        $body = $null
    }

    Write-Host "  Created credential '$userName' on the target."
    return $created
}

function Resolve-VBRVsaWindowsCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [object]         $Payload
    )

    if ((Get-VBRServerPlatform -Connection $Connection) -ne 'Linux') { return }

    $invalid = @(@($Payload.windowsHosts) | Where-Object {
        $_ -and -not (Test-VBRVsaCredentialFormat ([string]$_.credentials.credentialsName)) })

    foreach ($h in $invalid) {
        $picked = Select-VBRVsaCredential -Connection $Connection -HostName $h.name `
            -Reason "Uses '$($h.credentials.credentialsName)', which a VSA can't use."
        $h.credentials = [pscustomobject]@{
            credentialsName = [string]$picked.username
            credentialsTag  = [string]$picked.uniqueId
        }
    }
}

function Select-VBRVsaCredential {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $HostName,
        [string]                                $Reason
    )

    while ($true) {
        $usable = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/credentials' |
                    Where-Object { Test-VBRVsaCredentialFormat ([string]$_.username) })

        Write-Host "`n  Windows host: $HostName"
        if ($Reason) { Write-Host "    $Reason" }
        Write-Host "    Credentials on the target in FQDN\user or UPN form:"
        if ($usable.Count -eq 0) { Write-Host "      (none)" }
        for ($i = 0; $i -lt $usable.Count; $i++) {
            Write-Host "      [$($i + 1)] $($usable[$i].username) — $($usable[$i].description)"
        }
        Write-Host "      [N] Add a new credential now"
        Write-Host "      [M] Add one manually on the VSA, then refresh this list"
        Write-Host "      [Q] Abort the import"

        $range  = switch ($usable.Count) { 0 { '' } 1 { '1, ' } default { "1-$($usable.Count), " } }
        $answer = Read-Host "    Choose $($range)N, M or Q"

        $choice = 0
        if ([int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $usable.Count) {
            return $usable[$choice - 1]
        }
        switch -Regex ($answer) {
            '^[Nn]$' {
                $created = New-VBRVsaCredential -Connection $Connection
                if ($created -and $created.uniqueId) { return $created }
            }
            '^[Mm]$' { Read-Host "    Add the credential in the VSA console (Credentials and Passwords), then press Enter to refresh" | Out-Null }
            '^[Qq]$' { throw "Import aborted while choosing a credential for Windows host '$HostName'." }
        }
    }
}

function Get-VBRVsaInvalidWindowsHost {
    param([Parameter(Mandatory)] [string] $InputPath)

    $mgrFile = Join-Path $InputPath 'ManagedServers.json'
    if (-not (Test-Path $mgrFile)) { return }
    $mgr = Get-Content $mgrFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20

    @($mgr.windowsHosts) | Where-Object {
        $_ -and -not (Test-VBRVsaCredentialFormat ([string]$_.credentials.credentialsName))
    }
}

function Get-VBRVsaCredentialCandidate {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath
    )

    $names = [System.Collections.Generic.List[string]]::new()

    $credFile = Join-Path $InputPath 'Credentials.json'
    if (Test-Path $credFile) {
        $exported = Get-Content $credFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        foreach ($c in @($exported.credentials)) { if ($c.username) { $names.Add([string]$c.username) } }
    }
    foreach ($c in @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/credentials')) {
        if ($c.username) { $names.Add([string]$c.username) }
    }

    $names | Where-Object { Test-VBRVsaCredentialFormat $_ } | Sort-Object -Unique
}

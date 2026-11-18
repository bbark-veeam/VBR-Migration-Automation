# Import-VBRRepository
# Imports repositories using a hybrid approach to work around two API limitations:
#   - Non-cloud repos are submitted in bulk to /automation/repositories/import
#     (the Automation API).
#   - Cloud repos are submitted one at a time to
#     /backupInfrastructure/repositories?overwriteOwner=true so they can adopt
#     buckets already managed by another Veeam server. The Automation API has
#     no ownership-takeover parameter and would fail validation in that case.
#
# When -SourceVBR is specified, any repository that references the source VBR
# as its gateway (mountServer.mountServerName, account.connectionSettings
# .gatewayServers, or proxyAppliance.managedServerId) is remapped to use the
# target VBR itself before submission.
#
# Re-runs are safe: repositories already present on the target (matched by name)
# are filtered out for both the bulk Automation API path and the per-repo
# cloud path.

function Import-VBRRepository {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "Repositories.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "Repositories.json not found in $InputPath — skipping."
        return
    }

    $payload = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20

    $count = ($payload.PSObject.Properties |
              ForEach-Object { @($_.Value).Count } |
              Measure-Object -Sum).Sum
    if ($count -eq 0) {
        Write-Host "  No repositories in export — skipping."
        return
    }

    # Cloud repository categories — handled separately because they need
    # /backupInfrastructure/repositories?overwriteOwner=true to adopt buckets.
    $cloudCategories = @(
        'AzureBlobStorages'
        'AzureDataBoxStorages'
        'AmazonS3Storages'
        'AmazonSnowballEdgeStorages'
        'S3CompatibleStorages'
        'GoogleCloudStorages'
        'IBMCloudStorages'
        'AmazonS3GlacierStorages'
        'AzureArchiveStorages'
        'WasabiCloudStorages'
    )

    # Resolve the target VBR's own managed-server entry. Needed for both
    # gateway remap (rebuilds mountServer block) and the cloud-repo
    # transformation (mountServerId references on the regular endpoint).
    $targetId   = $null
    $targetSelf = $null
    try {
        $targetServers = Invoke-RestMethod `
            -Uri "$($Connection.BaseUri)/backupInfrastructure/managedServers" `
            -Method Get -Headers $Connection.Headers -SkipCertificateCheck
    } catch {
        Write-Warning "  Could not query target managed servers: $($_.Exception.Message)"
        $targetServers = $null
    }

    if ($targetServers -and $TargetVBR) {
        $targetSelf = $targetServers.data |
            Where-Object { $_.name -eq $TargetVBR } |
            Select-Object -First 1
    }

    if ($null -ne $targetSelf) {
        $targetId = if ($targetSelf.uniqueId) { $targetSelf.uniqueId }
                    elseif ($targetSelf.id)   { $targetSelf.id }
                    else                      { $null }

        if ($targetId) {
            Write-Host "  Target VBR managed-server identifier: $targetId"
        }
    }

    # The target's own entry may differ in case from -Server (e.g. a VSA lists
    # itself in lower case); mount server names are validated case-sensitively.
    $targetName = if ($targetSelf -and $targetSelf.name) { [string]$targetSelf.name } else { $TargetVBR }

    # Gateway remap when source VBR is the gateway.
    if ($SourceVBR -and $TargetVBR -and $targetId) {
        $remapped = 0
        foreach ($prop in @($payload.PSObject.Properties)) {
            foreach ($repo in @($prop.Value)) {
                $isSourceGateway = $false

                if ($repo.mountServer.linux.mountServerName -eq $SourceVBR)   { $isSourceGateway = $true }
                if ($repo.mountServer.windows.mountServerName -eq $SourceVBR) { $isSourceGateway = $true }
                if ($repo.account.connectionSettings.gatewayServers -contains $SourceVBR) { $isSourceGateway = $true }

                if (-not $isSourceGateway) { continue }

                Write-Host "  Remapping gateway for '$($repo.name)' from $SourceVBR -> $targetName"

                if ($targetSelf.type -eq 'WindowsHost') {
                    $repo.mountServer = [pscustomobject]@{
                        mountServerSettingsType = 'Windows'
                        windows = [pscustomobject]@{
                            mountServerName       = $targetName
                            writeCacheFolder      = 'C:\ProgramData\Veeam\Backup\IRCache\'
                            vPowerNFSEnabled      = $true
                            vPowerNFSPortSettings = [pscustomobject]@{
                                mountPort     = 1058
                                vPowerNFSPort = 2049
                            }
                        }
                    }
                } else {
                    $repo.mountServer = [pscustomobject]@{
                        mountServerSettingsType = 'Linux'
                        linux = [pscustomobject]@{
                            mountServerName       = $targetName
                            writeCacheFolder      = '/var/lib/veeamdata/veeam/IRCache/'
                            vPowerNFSEnabled      = $true
                            vPowerNFSPortSettings = [pscustomobject]@{
                                mountPort     = 1058
                                vPowerNFSPort = 2049
                            }
                        }
                    }
                }

                if ($repo.proxyAppliance -and $targetId) {
                    $repo.proxyAppliance.managedServerId = $targetId
                }

                if ($repo.account.connectionSettings.gatewayServers) {
                    $newGateways = @($repo.account.connectionSettings.gatewayServers | ForEach-Object {
                        if ($_ -ieq $SourceVBR) { $targetName } else { $_ }
                    })
                    $repo.account.connectionSettings.gatewayServers = $newGateways
                }

                $remapped++
            }
        }
        if ($remapped -gt 0) {
            Write-Host "  Remapped $remapped repository gateway reference(s) to target VBR."
        }
    }

    # Separate cloud repos from non-cloud repos.
    $cloudRepos = @()
    foreach ($c in $cloudCategories) {
        foreach ($repo in @($payload.$c)) {
            $cloudRepos += [pscustomobject]@{ Category = $c; Repo = $repo }
        }
        $payload.$c = @()
    }

    if ($SkipCloudRepos -and $cloudRepos.Count -gt 0) {
        Write-Warning "  -SkipCloudRepos is set — skipping $($cloudRepos.Count) cloud repository/ies. Recreate them manually via the Veeam console."
        $cloudRepos = @()
    }

    # Build a uniqueId -> target-cloud-credential map. The regular repository
    # endpoint references credentials by their database `id`, not by `uniqueId`,
    # so source values must be translated before POSTing.
    $cloudCredsById = @{}
    if ($cloudRepos.Count -gt 0) {
        try {
            $targetCloudCreds = Invoke-RestMethod `
                -Uri "$($Connection.BaseUri)/cloudCredentials" `
                -Method Get -Headers $Connection.Headers -SkipCertificateCheck
            foreach ($cc in @($targetCloudCreds.data)) {
                if ($cc.uniqueId) { $cloudCredsById[$cc.uniqueId] = $cc }
            }
        } catch {
            Write-Warning "  Could not query target cloud credentials: $($_.Exception.Message)"
        }
    }

    # Build the set of repository names already on the target. Shared by both
    # the non-cloud filter (Automation API) and the cloud-repo skip-if-exists
    # check.
    $existingRepoNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $nonCloudCount = ($payload.PSObject.Properties |
                      ForEach-Object { @($_.Value).Count } |
                      Measure-Object -Sum).Sum

    if ($nonCloudCount -gt 0 -or $cloudRepos.Count -gt 0) {
        try {
            $targetRepos = Invoke-RestMethod `
                -Uri "$($Connection.BaseUri)/backupInfrastructure/repositories" `
                -Method Get -Headers $Connection.Headers -SkipCertificateCheck
            foreach ($r in @($targetRepos.data)) {
                if ($r.name) { $existingRepoNames.Add($r.name) | Out-Null }
            }
        } catch {
            Write-Warning "  Could not query existing repositories — skip-if-exists check disabled: $($_.Exception.Message)"
        }
    }

    # Filter non-cloud repos against the existing-name set.
    if ($nonCloudCount -gt 0) {
        $totalSkipped = 0
        foreach ($prop in @($payload.PSObject.Properties)) {
            $original = @($prop.Value)
            if ($original.Count -eq 0) { continue }

            $kept    = @($original | Where-Object { -not $existingRepoNames.Contains($_.name) })
            $skipped = $original.Count - $kept.Count
            if ($skipped -gt 0) {
                Write-Host "  Skipping $skipped $($prop.Name) already present on target."
                $payload.($prop.Name) = $kept
                $totalSkipped += $skipped
            }
        }

        $nonCloudCount = ($payload.PSObject.Properties |
                          ForEach-Object { @($_.Value).Count } |
                          Measure-Object -Sum).Sum
    }

    if ($nonCloudCount -gt 0) {
        $rawJson = $payload | ConvertTo-Json -Depth 20

        $debugFile = Join-Path $InputPath "_Repositories.posted.json"
        $rawJson | Set-Content -Path $debugFile -Encoding UTF8

        Write-Host "Importing $nonCloudCount non-cloud repository/ies via Automation API..."
        Invoke-AutomationSession `
            -Connection $Connection `
            -Endpoint   '/automation/repositories/import' `
            -Body       $rawJson `
            -Quiet:$Quiet
        Write-Host "  Non-cloud repository import completed."
    } elseif ($cloudRepos.Count -eq 0) {
        Write-Host "  All repositories already exist on target — nothing to import."
    }

    # Import cloud repos one at a time via the regular endpoint with
    # overwriteOwner=true (to adopt buckets already managed by another VBR).
    foreach ($entry in $cloudRepos) {
        $repo     = $entry.Repo
        $category = $entry.Category

        if ($existingRepoNames.Contains($repo.name)) {
            Write-Host "  Skipping cloud repository '$($repo.name)' ($category) — already exists on target."
            continue
        }

        Write-Host "Adopting cloud repository '$($repo.name)' ($category)..."

        # Transform automation-export schema -> regular endpoint schema:
        #   - account.credentials.tag (uniqueId) -> account.credentialsId (target's database `id`)
        #   - enableTaskLimit -> taskLimitEnabled
        #   - mountServer.{linux|windows}.mountServerName -> mountServerId (regular endpoint uses ID refs)
        #   - add importBackup, importIndex (so existing data is preserved)
        $sourceCredTag = $repo.account.credentials.tag
        $targetCred    = $cloudCredsById[$sourceCredTag]
        if (-not $targetCred -or -not $targetCred.id) {
            Write-Error "  Cannot find target cloud credential with uniqueId '$sourceCredTag' for repo '$($repo.name)'. Skipping."
            continue
        }

        $newAccount = [pscustomobject]@{
            regionId           = $repo.account.regionId
            credentialsId      = $targetCred.id
            connectionSettings = $repo.account.connectionSettings
        }

        if (-not $targetId) {
            Write-Error "  Cannot adopt cloud repository '$($repo.name)' — target VBR managed-server ID was not resolved. Skipping."
            continue
        }

        # Build the mountServer block with ID-based references (regular endpoint requirement).
        $newMountServer = [pscustomobject]@{
            mountServerSettingsType = $repo.mountServer.mountServerSettingsType
        }
        if ($repo.mountServer.windows) {
            $w = $repo.mountServer.windows
            $newMountServer | Add-Member -NotePropertyName windows -NotePropertyValue ([pscustomobject]@{
                mountServerId         = $targetId
                writeCacheFolder      = $w.writeCacheFolder
                vPowerNFSEnabled      = $w.vPowerNFSEnabled
                vPowerNFSPortSettings = $w.vPowerNFSPortSettings
            })
        }
        if ($repo.mountServer.linux) {
            $l = $repo.mountServer.linux
            $newMountServer | Add-Member -NotePropertyName linux -NotePropertyValue ([pscustomobject]@{
                mountServerId         = $targetId
                writeCacheFolder      = $l.writeCacheFolder
                vPowerNFSEnabled      = $l.vPowerNFSEnabled
                vPowerNFSPortSettings = $l.vPowerNFSPortSettings
            })
        }

        $body = [ordered]@{
            type             = $repo.type
            name             = $repo.name
            description      = $repo.description
            uniqueId         = $repo.uniqueId
            account          = $newAccount
            bucket           = $repo.bucket
            mountServer      = $newMountServer
            importBackup     = $true
            importIndex      = $true
            taskLimitEnabled = [bool]$repo.enableTaskLimit
            maxTaskCount     = $repo.maxTaskCount
        }
        if ($repo.proxyAppliance) {
            $body['proxyAppliance'] = $repo.proxyAppliance
        }

        $bodyJson = $body | ConvertTo-Json -Depth 20

        # Save the posted body for diagnostic inspection.
        $debugFile = Join-Path $InputPath "_Repositories.cloud.$($repo.name -replace '[^\w\-]', '_').posted.json"
        $bodyJson | Set-Content -Path $debugFile -Encoding UTF8

        try {
            $response = Invoke-RestMethod `
                -Uri "$($Connection.BaseUri)/backupInfrastructure/repositories?overwriteOwner=true" `
                -Method Post `
                -Headers $Connection.Headers `
                -Body $bodyJson `
                -SkipCertificateCheck
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $_.ErrorDetails.Message
            } else {
                $_.Exception.Message
            }
            $details    = Format-RedactedJson -Text $details
            Write-Error "  Failed to adopt cloud repository '$($repo.name)' (HTTP $statusCode).`n  Response: $details"
            continue
        }

        Write-Host "  Cloud repository '$($repo.name)' adopted (overwriteOwner=true, importBackup=true)."
    }

    Write-Host "  Repositories import completed."
}

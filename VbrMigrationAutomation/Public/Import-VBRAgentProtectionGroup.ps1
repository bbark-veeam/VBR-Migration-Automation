# Import-VBRAgentProtectionGroup
# Recreates Veeam Agent protection groups on the target VBR server using a
# two-step flow:
#   1. POST /agents/protectionGroups          — creates the group (async session)
#   2. PUT  /agents/protectionGroups/{newId}  — applies full configuration (options)
#
# For ADObjects-type groups, the target VBR is checked for the source's AD
# domain configuration and, if missing, it is registered automatically via
# POST /adDomains using the corresponding migrated credential.
#
# Credential references throughout the protection group body (master,
# customCredentials, domainControllerSettings) are remapped from source
# uniqueId form to the target's database id before POST.
#
# Writes AgentProtectionGroupMap.json (sourceId -> targetId) for
# Import-VBRAgentJob, which depends on it to remap protection-group references
# inside agent job bodies.

function Import-VBRAgentProtectionGroup {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "AgentProtectionGroups.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "AgentProtectionGroups.json not found in $InputPath — skipping."
        return
    }

    $groups = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    if (@($groups).Count -eq 0) {
        Write-Host "  No protection groups in export — skipping."
        return
    }

    Write-Host "Importing Agent Protection Groups..."

    # Pre-fetch existing protection groups so duplicates are skipped on re-runs.
    # The UUID mapping (source id -> target id) is still recorded for skipped
    # groups because Import-VBRAgentJob depends on the map to remap job
    # references on re-runs.
    $existingGroupsByName = @{}
    try {
        $existingGroups = Get-VBRPaginatedData -Connection $Connection -Endpoint '/agents/protectionGroups'
        foreach ($g in $existingGroups) {
            if ($g.name) { $existingGroupsByName[$g.name] = $g }
        }
    } catch {
        Write-Warning "  Could not query existing protection groups — skip-if-exists check disabled: $($_.Exception.Message)"
    }

    # Build a source-uniqueId -> target-id map for credentials. Regular CRUD
    # endpoints (e.g. /adDomains, protection group POST) reference credentials
    # by their database `id`, not by `uniqueId`. Any credentialsId carried over
    # from the source export is in uniqueId form and must be translated.
    $credUniqueIdToId = @{}
    try {
        $targetCreds = [pscustomobject]@{ data = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/credentials') }
        foreach ($c in @($targetCreds.data)) {
            if ($c.uniqueId -and $c.id) { $credUniqueIdToId[$c.uniqueId] = $c.id }
        }
        Write-Host "  Built credential map: $($credUniqueIdToId.Count) credential(s) on target."
    } catch {
        Write-Warning "  Could not query target credentials — credential remap disabled: $($_.Exception.Message)"
    }

    # Helper: remap a source credential uniqueId to the target's database id.
    # Returns the input unchanged when no mapping exists, which leaves
    # all-zeros placeholders intact.
    function Resolve-TargetCredId {
        param([string] $SourceUniqueId)
        if ([string]::IsNullOrWhiteSpace($SourceUniqueId))     { return $SourceUniqueId }
        if ($SourceUniqueId -eq '00000000-0000-0000-0000-000000000000') { return $SourceUniqueId }
        if ($credUniqueIdToId.ContainsKey($SourceUniqueId))    { return $credUniqueIdToId[$SourceUniqueId] }
        return $SourceUniqueId
    }

    $map = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($group in $groups) {
        # ManuallyAdded is a system default — every VBR server already has one.
        if ($group.type -eq 'ManuallyAdded') {
            Write-Host "  Skipping '$($group.name)' (ManuallyAdded — system default)."
            continue
        }

        # If a group with this name already exists on the target, skip creation
        # but still record the UUID mapping so jobs that depend on it can
        # resolve their protectionGroupId references on a re-run.
        if ($existingGroupsByName.ContainsKey($group.name)) {
            $existing = $existingGroupsByName[$group.name]
            Write-Host "  Skipping '$($group.name)' — already exists on target (id: $($existing.id))."
            $map.Add(@{
                sourceName = $group.name
                sourceId   = $group.id
                targetId   = $existing.id
            })
            continue
        }

        $sourceId = $group.id

        # ADObjects: ensure the target has the source's AD domain configured.
        if ($group.type -eq 'ADObjects') {
            $sourceDC         = $group.activeDirectory.domainControllerSettings
            $sourceDomainName = $sourceDC.name

            $targetDomains = Get-VBRPaginatedData -Connection $Connection -Endpoint '/adDomains'
            $targetDomain  = $targetDomains | Where-Object { $_.name -eq $sourceDomainName } | Select-Object -First 1

            if ($null -eq $targetDomain) {
                Write-Host "  Target VBR has no AD domain '$sourceDomainName' — creating it..."

                # /adDomains POST references credentials by their database `id`,
                # NOT `uniqueId`. Use the credential map built above.
                $targetCredId = Resolve-TargetCredId $sourceDC.credentialsId
                if ($targetCredId -eq $sourceDC.credentialsId) {
                    throw "Cannot find target credential with uniqueId '$($sourceDC.credentialsId)' for AD domain '$sourceDomainName'. Run Import-VBRCredential first to migrate credentials."
                }

                $domainBody = @{
                    serverName    = $sourceDC.serverName
                    port          = $sourceDC.port
                    credentialsId = $targetCredId
                } | ConvertTo-Json

                try {
                    $targetDomain = Invoke-RestMethod -Uri "$($Connection.BaseUri)/adDomains" `
                        -Method Post -Headers $Connection.Headers `
                        -Body $domainBody -SkipCertificateCheck
                } catch {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                    $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                        $_.ErrorDetails.Message
                    } else {
                        $_.Exception.Message
                    }
                    $details    = Format-RedactedJson -Text $details
                    throw "Failed to create AD domain '$sourceDomainName' (HTTP $statusCode).`n  Response: $details`n  This usually means the credential UUID '$($sourceDC.credentialsId)' does not exist on the target. Run Import-VBRCredential first to migrate credentials."
                }

                Write-Host "    AD domain created — id: $($targetDomain.id)"
            } else {
                Write-Host "  Found AD domain '$sourceDomainName' on target — id: $($targetDomain.id)"
            }

            # Substitute the target's domain UUID into all references in the
            # protection group body. When the target's UUID matches the source's
            # (because the AD domain id is derived from AD itself), this is a no-op.
            $group.activeDirectory.domainControllerSettings.id            = $targetDomain.id
            $group.activeDirectory.domainControllerSettings.credentialsId = $targetDomain.credentialsId

            foreach ($obj in @($group.activeDirectory.objects)) {
                $obj.domainId = $targetDomain.id
                # obj.id is the AD computer's objectGUID — stable across servers, leave as-is
            }

            if ($group.credentials.customCredentials) {
                foreach ($cc in @($group.credentials.customCredentials)) {
                    if ($cc.object) {
                        $cc.object.domainId = $targetDomain.id
                        # cc.object.id is the AD computer's objectGUID — leave as-is
                    }
                    if ($cc.credentialsId) {
                        $cc.credentialsId = Resolve-TargetCredId $cc.credentialsId
                    }
                }
            }

            if ($group.credentials.masterCredentialsId) {
                $group.credentials.masterCredentialsId = Resolve-TargetCredId $group.credentials.masterCredentialsId
            }
            # domainControllerSettings.credentialsId is set above from the AD domain
            # record, but that value may still be a uniqueId form when an existing
            # domain was found on the target. Force the remap to ensure it ends up
            # as the target's database id.
            $group.activeDirectory.domainControllerSettings.credentialsId =
                Resolve-TargetCredId $group.activeDirectory.domainControllerSettings.credentialsId
        }

        # Build POST body (no options, no id, no isDisabled — these are PUT-only or read-only).
        $postBody = $group | Select-Object -Property * -ExcludeProperty id, isDisabled, options

        Write-Host "  Creating '$($group.name)' (type: $($group.type))..."

        # POST returns an async session — Invoke-AutomationSession polls until terminal.
        Invoke-AutomationSession `
            -Connection $Connection `
            -Endpoint   '/agents/protectionGroups' `
            -Body       $postBody `
            -Quiet:$Quiet

        # Look up the new group by name to get the target ID assigned during creation.
        $allGroups = Get-VBRPaginatedData -Connection $Connection -Endpoint '/agents/protectionGroups'
        $newGroup  = $allGroups | Where-Object { $_.name -eq $group.name } | Select-Object -First 1

        if ($null -eq $newGroup) {
            throw "Protection group '$($group.name)' was not found after creation."
        }

        Write-Host "    Created with id: $($newGroup.id)"

        # Build PUT body: target's GET result + source's options. The target's
        # GET result is used as the base so any UUIDs the target generated during
        # discovery are preserved; only the configuration block (`options`) is
        # overlaid from the source.
        $putBody = $newGroup
        $putBody | Add-Member -NotePropertyName options -NotePropertyValue $group.options -Force

        # Zero out source-specific distribution UUIDs so VBR uses its own defaults.
        if ($putBody.options) {
            if ($putBody.options.distributionServerId) {
                $putBody.options.distributionServerId     = '00000000-0000-0000-0000-000000000000'
            }
            if ($putBody.options.distributionRepositoryId) {
                $putBody.options.distributionRepositoryId = '00000000-0000-0000-0000-000000000000'
            }
        }

        # PUT applies the configuration. May return an async session — handled by Invoke-AutomationSession.
        Invoke-AutomationSession `
            -Connection $Connection `
            -Endpoint   "/agents/protectionGroups/$($newGroup.id)" `
            -Method     Put `
            -Body       $putBody `
            -Quiet:$Quiet | Out-Null

        Write-Host "    Configuration applied."

        $map.Add(@{
            sourceName = $group.name
            sourceId   = $sourceId
            targetId   = $newGroup.id
        })
    }

    $mapFile = Join-Path $InputPath "AgentProtectionGroupMap.json"
    $map.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -Path $mapFile -Encoding UTF8

    Write-Host "  UUID map saved to $mapFile"
    Write-Host "  Agent Protection Groups import completed ($($map.Count) group(s))."
}

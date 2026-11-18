# Sync-VBRJobHostName
# Rewrites vSphere host references in a job import payload to the exact host
# names the target's inventory reports. Job validation compares host names and
# URNs case-sensitively, and a target that registered a host before keeps its
# original casing, so a name that differs only in case fails validation.
# References to hosts the target doesn't know are left unchanged.

function Sync-VBRJobHostName {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [object]         $Payload
    )

    try {
        $response = [pscustomobject]@{ data = @(Get-VBRPaginatedData -Connection $Connection -Endpoint '/inventory/vmware/hosts') }
    } catch {
        Write-Warning "  Could not read the target's vSphere inventory — host names not checked: $($_.Exception.Message)"
        return
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($h in @($response.data)) { if ($h.name) { $names.Add([string]$h.name) } }

    $rewritten = Update-VBRHostNameCasing -Node $Payload -HostNames $names
    foreach ($change in $rewritten) {
        Write-Host "  Host name aligned to target inventory: $change"
    }
}

function Update-VBRHostNameCasing {
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Node,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $HostNames
    )

    $canonical = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $HostNames) { if (-not $canonical.ContainsKey($n)) { $canonical[$n] = $n } }

    $changes = [System.Collections.Generic.SortedSet[string]]::new()
    if ($canonical.Count -gt 0) { Update-HostNameNode -Node $Node -Canonical $canonical -Changes $changes }
    return @($changes)
}

function Update-HostNameNode {
    param($Node, $Canonical, $Changes)

    if ($null -eq $Node -or $Node -is [string]) { return }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [System.Management.Automation.PSCustomObject]) {
        foreach ($item in $Node) { Update-HostNameNode -Node $item -Canonical $Canonical -Changes $Changes }
        return
    }

    if ($Node -isnot [System.Management.Automation.PSCustomObject]) { return }

    $isHostObject = $Node.PSObject.Properties['type'] -and $Node.type -eq 'Host'

    foreach ($prop in @($Node.PSObject.Properties)) {
        $value = $prop.Value

        if ($value -is [string]) {
            $isHostField = $prop.Name -eq 'hostName' -or
                           ($isHostObject -and $prop.Name -in @('name', 'objectId'))

            if ($isHostField -and $Canonical.ContainsKey($value) -and $Canonical[$value] -cne $value) {
                $Changes.Add("$value -> $($Canonical[$value])") | Out-Null
                $prop.Value = $Canonical[$value]
            }
            elseif ($prop.Name -eq 'urn' -and $value -match '^(?<scheme>[^:;]+):(?<host>[^;]+)(?<rest>;.*)?$') {
                $urnHost = $Matches['host']
                if ($Canonical.ContainsKey($urnHost) -and $Canonical[$urnHost] -cne $urnHost) {
                    $Changes.Add("$urnHost -> $($Canonical[$urnHost])") | Out-Null
                    $prop.Value = "$($Matches['scheme']):$($Canonical[$urnHost])$($Matches['rest'])"
                }
            }
        }
        else {
            Update-HostNameNode -Node $value -Canonical $Canonical -Changes $Changes
        }
    }
}

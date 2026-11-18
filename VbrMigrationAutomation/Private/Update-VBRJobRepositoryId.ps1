# Update-VBRJobRepositoryId
# Agent jobs are created through the regular /jobs endpoint, which needs each
# repository's ID on the target. The export holds the source IDs, and an
# imported repository can get a new ID on the target. This rewrites every
# backupRepositoryId in a job body: source ID -> repository name (from
# Repositories.json) -> that repository's ID on the target.
#
# New-VBRRepositoryIdResolver builds the lookup once per import;
# Update-VBRJobRepositoryId applies it to one job and returns the IDs it could
# not resolve.

function New-VBRRepositoryIdResolver {
    param(
        [Parameter(Mandatory)] [string] $InputPath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $TargetRepositories
    )

    $sourceNames = @{}
    $repoFile = Join-Path $InputPath 'Repositories.json'
    if (Test-Path $repoFile) {
        $exported = Get-Content $repoFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        foreach ($repo in @($exported.PSObject.Properties | ForEach-Object { @($_.Value) })) {
            if ($repo -and $repo.uniqueId -and $repo.name) {
                $sourceNames[(ConvertTo-VBRIdKey $repo.uniqueId)] = [string]$repo.name
            }
        }
    }

    $targetIds   = @{}
    $targetNames = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($repo in $TargetRepositories) {
        if (-not $repo.id) { continue }
        $targetIds[(ConvertTo-VBRIdKey $repo.id)] = [string]$repo.id
        if ($repo.name -and -not $targetNames.ContainsKey($repo.name)) { $targetNames[$repo.name] = [string]$repo.id }
    }

    [pscustomobject]@{ SourceNames = $sourceNames; TargetIds = $targetIds; TargetNames = $targetNames }
}

function Update-VBRJobRepositoryId {
    param(
        [Parameter(Mandatory)] [object]         $Job,
        [Parameter(Mandatory)] [PSCustomObject] $Resolver
    )

    $unresolved = [System.Collections.Generic.List[string]]::new()
    Update-RepositoryIdNode -Node $Job -Resolver $Resolver -Unresolved $unresolved
    return @($unresolved)
}

function Update-RepositoryIdNode {
    param($Node, $Resolver, $Unresolved)

    if ($null -eq $Node -or $Node -is [string]) { return }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [System.Management.Automation.PSCustomObject]) {
        foreach ($item in $Node) { Update-RepositoryIdNode -Node $item -Resolver $Resolver -Unresolved $Unresolved }
        return
    }
    if ($Node -isnot [System.Management.Automation.PSCustomObject]) { return }

    foreach ($prop in @($Node.PSObject.Properties)) {
        if ($prop.Name -eq 'backupRepositoryId' -and $prop.Value -is [string] -and $prop.Value) {
            $key = ConvertTo-VBRIdKey $prop.Value
            if ($key -eq '00000000000000000000000000000000') { continue }

            if ($Resolver.TargetIds.ContainsKey($key)) {
                $prop.Value = $Resolver.TargetIds[$key]
            } elseif ($Resolver.SourceNames.ContainsKey($key) -and
                      $Resolver.TargetNames.ContainsKey($Resolver.SourceNames[$key])) {
                $prop.Value = $Resolver.TargetNames[$Resolver.SourceNames[$key]]
            } else {
                $name = if ($Resolver.SourceNames.ContainsKey($key)) { " ('$($Resolver.SourceNames[$key])')" } else { '' }
                $Unresolved.Add("$($prop.Value)$name")
            }
        } else {
            Update-RepositoryIdNode -Node $prop.Value -Resolver $Resolver -Unresolved $Unresolved
        }
    }
}

function ConvertTo-VBRIdKey {
    param([Parameter(Mandatory)] [string] $Id)
    return ($Id -replace '[{}-]', '').ToLowerInvariant()
}

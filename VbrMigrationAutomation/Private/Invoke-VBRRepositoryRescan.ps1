# Invoke-VBRRepositoryRescan
# Offers to rescan the repositories an import created on the target, so the
# backups already stored in them show up (under Backups > Disk (Imported)).
# Importing a repository through the Automation API does not import its
# existing backups. Declining leaves the repositories in place; they can be
# rescanned later from the console when the data is needed.
#
# A failed rescan is reported as a warning: the configuration import itself
# has already completed.

function Invoke-VBRRepositoryRescan {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $RepositoryNames,
        [int]    $TimeoutSeconds = 7200,
        [switch] $Quiet
    )

    if ($RepositoryNames.Count -eq 0) {
        Write-Host "  No repositories were imported in this run — nothing to rescan."
        return
    }

    try {
        $targetRepos = Get-VBRPaginatedData -Connection $Connection -Endpoint '/backupInfrastructure/repositories'
    } catch {
        Write-Warning "  Could not list target repositories — rescan skipped: $($_.Exception.Message)"
        return
    }

    $wanted  = [System.Collections.Generic.HashSet[string]]::new([string[]]$RepositoryNames, [System.StringComparer]::OrdinalIgnoreCase)
    $toScan  = @($targetRepos | Where-Object { $_.name -and $wanted.Contains($_.name) })

    if ($toScan.Count -eq 0) {
        Write-Warning "  None of the imported repositories were found on the target — rescan skipped."
        return
    }

    Write-Host "  Imported repositories:"
    foreach ($r in $toScan) { Write-Host "    - $($r.name)" }
    Write-Host "  A rescan makes the backups already in them available for restore (Backups > Disk (Imported))."
    Write-Host "  On large repositories this can take a while. You can skip it and rescan later from the console."

    $answer = Read-Host "Rescan imported repositories now? [y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Host "  Rescan skipped."
        return
    }

    $body = @{ repositoryIds = @($toScan | ForEach-Object { $_.id }) }

    try {
        Invoke-AutomationSession `
            -Connection     $Connection `
            -Endpoint       '/backupInfrastructure/repositories/rescan' `
            -Body           $body `
            -TimeoutSeconds $TimeoutSeconds `
            -Quiet:$Quiet
        Write-Host "  Rescan completed. Map the imported backups to jobs from the console where needed."
    } catch {
        Write-Warning "  Repository rescan failed: $($_.Exception.Message)"
        Write-Warning "  The configuration import is complete. Rescan the repositories from the console instead."
    }
}

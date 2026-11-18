# Import-VBRJob
# Imports VMware vSphere primary backup jobs onto the target VBR server via
# the Automation API. Jobs that already exist on the target (matched by name)
# are filtered out before submission so re-runs are safe.

function Import-VBRJob {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $InputPath,
        [string]                                $SourceVBR,
        [string]                                $TargetVBR,
        [switch]                                $IsVSA,
        [switch]                                $SkipCloudRepos,
        [switch]                                $Quiet
    )

    $inFile = Join-Path $InputPath "Jobs.json"
    if (-not (Test-Path $inFile)) {
        Write-Warning "Jobs.json not found in $InputPath — skipping."
        return
    }

    $payload = Get-Content -Path $inFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    if (@($payload.jobs).Count -eq 0) {
        Write-Host "  No jobs in export — skipping."
        return
    }

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

    $original = @($payload.jobs)
    $kept     = @($original | Where-Object { -not $existingJobNames.Contains($_.name) })
    $skipped  = $original.Count - $kept.Count

    if ($skipped -gt 0) {
        Write-Host "  Skipping $skipped job(s) already present on target."
        $payload.jobs = $kept
    }

    if (@($payload.jobs).Count -eq 0) {
        Write-Host "  All jobs already exist on target — nothing to import."
        return
    }

    Write-Host "Importing $(@($payload.jobs).Count) job(s) from $inFile..."
    Sync-VBRJobHostName -Connection $Connection -Payload $payload

    $rawJson = $payload | ConvertTo-Json -Depth 20
    Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/jobs/import' `
        -Body       $rawJson `
        -Quiet:$Quiet

    Write-Host "  Jobs import completed."
}

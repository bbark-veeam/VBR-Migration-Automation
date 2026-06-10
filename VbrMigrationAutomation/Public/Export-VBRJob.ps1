# Export-VBRJob
# Exports VMware vSphere primary backup jobs from the source VBR server's
# automation API and writes them to Jobs.json. The Automation API tag supports
# vSphere primary jobs only — Hyper-V, agent, backup-copy, replication, and
# other job categories are not returned by this endpoint.

function Export-VBRJob {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting Jobs..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/jobs/export' `
        -Body       @{}

    $outFile = Join-Path $OutputPath "Jobs.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

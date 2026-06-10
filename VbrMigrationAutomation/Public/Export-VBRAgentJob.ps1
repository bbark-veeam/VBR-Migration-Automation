# Export-VBRAgentJob
# Exports Veeam Agent backup jobs (both standalone agent jobs and agent
# backup policies, for Windows and Linux) from the source VBR server and
# writes them to AgentJobs.json. Fetches all jobs from /jobs and filters
# client-side to the relevant agent-job types.

function Export-VBRAgentJob {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath
    )

    Write-Host "Exporting Agent Jobs..."

    $agentTypes = @(
        'WindowsAgentBackup'
        'LinuxAgentBackup'
        'WindowsAgentBackupWorkstationPolicy'
        'WindowsAgentBackupServerPolicy'
        'LinuxAgentBackupWorkstationPolicy'
        'LinuxAgentBackupServerPolicy'
    )

    $allJobs   = Get-VBRPaginatedData -Connection $Connection -Endpoint '/jobs'
    $agentJobs = @($allJobs | Where-Object { $_.type -in $agentTypes })

    if ($agentJobs.Count -eq 0) {
        Write-Host "  No agent jobs found — skipping."
        return
    }

    $outFile = Join-Path $OutputPath "AgentJobs.json"
    $agentJobs | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Exported $($agentJobs.Count) agent job(s) to $outFile"
}

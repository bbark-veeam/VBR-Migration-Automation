# Export-VBRAgentProtectionGroup
# Exports Veeam Agent protection groups from the source VBR server and writes
# them to AgentProtectionGroups.json. Uses the /agents/protectionGroups
# endpoint with pagination handled by Get-VBRPaginatedData.

function Export-VBRAgentProtectionGroup {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath
    )

    Write-Host "Exporting Agent Protection Groups..."

    $groups = Get-VBRPaginatedData -Connection $Connection -Endpoint '/agents/protectionGroups'

    if ($groups.Count -eq 0) {
        Write-Host "  No protection groups found — skipping."
        return
    }

    $outFile = Join-Path $OutputPath "AgentProtectionGroups.json"
    $groups | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Exported $($groups.Count) protection group(s) to $outFile"
}

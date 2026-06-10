# Export-VBRManagedServer
# Exports managed-server records (Windows hosts, Linux hosts, vSphere hosts,
# Cloud Director hosts) from the source VBR server's automation API and writes
# them to ManagedServers.json.

function Export-VBRManagedServer {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $OutputPath,
        [switch]                                $IsVSA,
        [string]                                $SourceFQDN
    )

    Write-Host "Exporting ManagedServers..."

    $result = Invoke-AutomationSession `
        -Connection $Connection `
        -Endpoint   '/automation/managedServers/export' `
        -Body       @{}

    $outFile = Join-Path $OutputPath "ManagedServers.json"
    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8

    Write-Host "  Saved to $outFile"
}

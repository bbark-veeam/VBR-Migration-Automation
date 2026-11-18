# Export-VBRMigration
# Orchestrates the main migration export: runs each per-component export
# function against the source VBR server and writes JSON artefacts to the
# output directory. Also writes a _metadata.json sidecar that the import side
# uses to auto-detect the source server and VSA flag.
#
# Export order:
#   1. Encryption Passwords
#   2. Credentials
#   3. Cloud Credentials
#   4. Managed Servers
#   5. Repositories
#   6. Proxies
#   7. Jobs
#
# Accepts an existing -Connection from a parent caller (e.g.
# Invoke-VBRMigrationExport) to avoid prompting for credentials a second time.

function Export-VBRMigration {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int]                           $Port       = 9419,
        [string]                        $OutputPath = (Get-VBRDefaultExportPath -Server $Server),
        [PSCustomObject]                $Connection
    )

    if ($Connection) {
        $conn = $Connection
        Write-Host "Using provided connection (skipping credential prompt)."
    } else {
        $cred = Get-Credential -Message "Enter credentials for $Server"
        $conn = Connect-VBRApi -Server $Server -Port $Port -Credential $cred
    }

    Write-Host "Checking automation endpoint availability..."
    try {
        $null = Invoke-RestMethod -Uri "$($conn.BaseUri)/automation/sessions" `
            -Method Get -Headers $conn.Headers -SkipCertificateCheck
        Write-Host "  Automation endpoint: OK"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            throw "Automation endpoint returned 404. The Automation API was introduced in VBR 12.1 (REST API v1.2). Verify your server version and license."
        }
        throw "Automation endpoint check failed (HTTP $statusCode): $($_.Exception.Message)"
    }

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # VSA-source detection. VSAs cannot be added as managed servers in another
    # Veeam installation, so any object that depends on the source VSA acting as
    # a managed server (e.g. LinuxHardened repos hosted on local VSA storage)
    # is filtered out of the export to prevent import failures downstream.
    $vsaAnswer = Read-Host "Is this Veeam server a VSA appliance? [y/N]"
    $isVSA     = ($vsaAnswer -match '^[Yy]')
    if ($isVSA) {
        Write-Host "  Source flagged as VSA — VSA-bound objects will be excluded from the export."
    }

    # Write export metadata so the import side can auto-detect source server, VSA flag, etc.
    $metadata = [ordered]@{
        sourceServer    = $Server
        isVSA           = [bool]$isVSA
        exportTimestamp = (Get-Date).ToString('o')
    }
    $metadataFile = Join-Path $OutputPath "_metadata.json"
    $metadata | ConvertTo-Json | Set-Content -Path $metadataFile -Encoding UTF8
    Write-Host "  Export metadata written to $metadataFile"

    $steps = @(
        @{ Name = 'EncryptionPasswords'; Func = 'Export-VBREncryptionPassword' }
        @{ Name = 'Credentials';         Func = 'Export-VBRCredential' }
        @{ Name = 'CloudCredentials';    Func = 'Export-VBRCloudCredential' }
        @{ Name = 'ManagedServers';      Func = 'Export-VBRManagedServer' }
        @{ Name = 'Repositories';        Func = 'Export-VBRRepository' }
        @{ Name = 'Proxies';             Func = 'Export-VBRProxy' }
        @{ Name = 'Jobs';                Func = 'Export-VBRJob' }
    )

    $failed = [System.Collections.Generic.List[string]]::new()

    foreach ($step in $steps) {
        Write-Host "`n--- $($step.Func) ---"
        try {
            & $step.Func -Connection $conn -OutputPath $OutputPath -IsVSA:$isVSA -SourceFQDN $Server
        } catch {
            Write-Error "  $($step.Func) FAILED: $_"
            $failed.Add($step.Func)
        }
    }

    Write-Host "`n========================================="
    if ($failed.Count -eq 0) {
        Write-Host "Export complete. Artefacts written to: $OutputPath"
    } else {
        Write-Warning "Export finished with $($failed.Count) failure(s):"
        $failed | ForEach-Object { Write-Warning "  - $_" }
        Write-Host "Artefacts that succeeded are in: $OutputPath"
    }
}

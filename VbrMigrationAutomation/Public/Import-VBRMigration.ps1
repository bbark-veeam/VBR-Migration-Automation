# Import-VBRMigration
# Orchestrates the main migration import: runs each per-component import
# function against the target VBR server in dependency order.
#
# Import order:
#   1. Encryption Passwords
#   2. Credentials
#   3. Cloud Credentials
#   4. Managed Servers
#   5. Source Server References (resolves repository host references not in
#      ManagedServers.json — typically the source VBR itself)
#   6. Repositories
#   7. Proxies
#   8. Jobs
#
# When the -InputPath directory contains a _metadata.json file written by the
# export side, -SourceVBR and -IsVSA are auto-populated from it unless the
# caller has supplied them explicitly. Accepts an existing -Connection from a
# parent caller (e.g. Invoke-VBRMigrationImport) to avoid prompting for
# credentials a second time, and supports -SkipBackupPrompt for the same
# reason on the configuration-backup decision.

function Import-VBRMigration {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int]                           $Port             = 9419,
        [string]                        $InputPath,
        [string]                        $SourceVBR,
        [switch]                        $IsVSA,
        [switch]                        $SkipCloudRepos,
        [PSCustomObject]                $Connection,
        [switch]                        $SkipBackupPrompt,
        [switch]                        $Quiet
    )

    $InputPath = Resolve-VBRImportPath -InputPath $InputPath

    # Auto-populate -SourceVBR and -IsVSA from the export's _metadata.json if
    # the caller didn't pass them explicitly. CLI args take precedence.
    $metadataFile = Join-Path $InputPath "_metadata.json"
    if (Test-Path $metadataFile) {
        try {
            $metadata = Get-Content -Path $metadataFile -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Host "Loaded export metadata from $metadataFile"

            if (-not $SourceVBR -and $metadata.sourceServer) {
                $SourceVBR = $metadata.sourceServer
                Write-Host "  -SourceVBR auto-set to '$SourceVBR' from metadata."
            }

            if (-not $IsVSA -and $metadata.isVSA) {
                $IsVSA = [switch]::Present
                Write-Host "  -IsVSA auto-set from metadata (source was flagged as a VSA at export time)."
            }
        } catch {
            Write-Warning "Could not parse metadata file: $($_.Exception.Message). Continuing without auto-population."
        }
    } else {
        Write-Host "No _metadata.json found in $InputPath — proceeding with CLI args only."
    }

    if ($Connection) {
        $conn = $Connection
        Write-Host "Using provided connection (skipping credential prompt)."
    } else {
        $cred = Get-Credential -Message "Enter credentials for $Server"
        $conn = Connect-VBRApi -Server $Server -Port $Port -Credential $cred
    }

    # Optional safety net: prompt to trigger a Veeam configuration backup before
    # any imports. When -SkipBackupPrompt is set, the prompt and backup
    # invocation are skipped (typically because a parent wrapper has already
    # handled the decision).
    if ($SkipBackupPrompt) {
        Write-Host "Configuration backup step delegated to caller (skipping local prompt)."
    } else {
        $answer = Read-Host "Create a Veeam configuration backup before importing? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
            Invoke-VBRConfigBackup -Connection $conn
        } else {
            Write-Warning "Skipping configuration backup. Proceed at your own risk."
        }
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

    $reposBefore = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $repoSnapshotOk = $true
    try {
        foreach ($r in (Get-VBRPaginatedData -Connection $conn -Endpoint '/backupInfrastructure/repositories')) {
            if ($r.name) { $reposBefore.Add($r.name) | Out-Null }
        }
    } catch {
        $repoSnapshotOk = $false
        Write-Warning "  Could not list target repositories before import — the rescan offer will be skipped: $($_.Exception.Message)"
    }

    $steps = @(
        'Import-VBREncryptionPassword'
        'Import-VBRCredential'
        'Import-VBRCloudCredential'
        'Import-VBRManagedServer'
        'Import-VBRSourceServerReference'
        'Import-VBRRepository'
        'Import-VBRProxy'
        'Import-VBRJob'
    )

    foreach ($func in $steps) {
        Write-Host "`n--- $func ---"
        try {
            & $func -Connection $conn -InputPath $InputPath -Quiet:$Quiet `
                    -SourceVBR $SourceVBR -TargetVBR $Server `
                    -IsVSA:$IsVSA -SkipCloudRepos:$SkipCloudRepos
        } catch {
            Write-Error "  $func FAILED: $_"
            throw "Import halted. Remaining steps were not run due to dependency-order requirements."
        }
    }

    if ($repoSnapshotOk) {
        Write-Host "`n--- Repository rescan ---"
        $exportedRepoNames = @()
        $repoFile = Join-Path $InputPath 'Repositories.json'
        if (Test-Path $repoFile) {
            $exported = Get-Content $repoFile -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
            $exportedRepoNames = @($exported.PSObject.Properties | ForEach-Object { @($_.Value) } |
                                   Where-Object { $_.name } | ForEach-Object { $_.name })
        }
        $importedRepoNames = @($exportedRepoNames | Where-Object { -not $reposBefore.Contains($_) } | Sort-Object -Unique)
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames $importedRepoNames -Quiet:$Quiet
    }

    Write-Host "`nImport complete."
}

# Invoke-VBRConfigBackup
# Triggers a Veeam Backup & Replication configuration backup via the REST API
# and waits for completion. Used as a safety step before destructive import
# operations to produce a known-good rollback point.
#
# Restoring from the configuration backup is not exposed by the REST API;
# restore must be performed through the Veeam console with VBR services stopped.

function Invoke-VBRConfigBackup {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [int] $PollIntervalSeconds = 5,
        [int] $TimeoutSeconds      = 600
    )

    $startEndpoint = '/configBackup/backup'
    $startUri      = "$($Connection.BaseUri)$startEndpoint"

    Write-Host "  Triggering configuration backup at $startUri ..."

    try {
        $response = Invoke-RestMethod -Uri $startUri -Method Post `
            -Headers $Connection.Headers -SkipCertificateCheck
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        $details    = Format-RedactedJson -Text $details
        throw "Configuration backup failed to start (HTTP $statusCode).`n  URL: $startUri`n  Response: $details"
    }

    # Config backup sessions are accessible at the general /sessions endpoint,
    # not under /automation/sessions.
    if (-not [string]::IsNullOrEmpty($response.id) -and $null -ne $response.state) {
        $sessionId = $response.id
        $statusUri = "$($Connection.BaseUri)/sessions/$sessionId"
        $deadline  = (Get-Date).AddSeconds($TimeoutSeconds)

        Write-Host "  Backup session $sessionId — polling..."

        do {
            Start-Sleep -Seconds $PollIntervalSeconds

            try {
                $status = Invoke-RestMethod -Uri $statusUri -Method Get `
                    -Headers $Connection.Headers -SkipCertificateCheck
            } catch {
                throw "Failed to poll backup session: $($_.Exception.Message)"
            }

            Write-Host "    [$((Get-Date).ToString('HH:mm:ss'))] State: $($status.state)"

            if ((Get-Date) -gt $deadline) {
                throw "Configuration backup timed out after $TimeoutSeconds seconds."
            }
        } while ($status.state -in @('Working', 'Running'))

        # Sessions reach state 'Stopped' on completion regardless of outcome.
        # The actual success/failure is in $status.result.result.
        $resultStatus = $status.result.result
        $resultMsg    = $status.result.message

        if ($resultStatus -eq 'Failed') {
            throw "Configuration backup failed: $resultMsg"
        }

        if ($resultStatus -eq 'Warning') {
            Write-Warning "Configuration backup completed with a warning: $resultMsg"
            Write-Host "  The backup file was created, but the warning above should be reviewed."
            $answer = Read-Host "Continue with import despite the warning? [y/N]"
            if ([string]::IsNullOrWhiteSpace($answer) -or $answer -notmatch '^[Yy]') {
                throw "Import cancelled by user after configuration backup warning."
            }
        }
    }

    Write-Host "  Configuration backup completed."
    Write-Host "  Default backup location on VBR server: C:\ProgramData\Veeam\Backup\VeeamConfigBackup"
}

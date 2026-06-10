# Invoke-AutomationSession
# Posts (or PUTs) to a VBR REST API endpoint and handles both synchronous and
# asynchronous response shapes:
#   - Export endpoints return data directly — returned as-is.
#   - Import / mutation endpoints return an async session object — polled until
#     terminal state, then the result.result field is inspected for outcome.
#
# Polling endpoint is selected by sessionType:
#   - "Automation" -> /api/v1/automation/sessions/{id}
#   - any other type (Infrastructure, ConfigBackup, ...) -> /api/v1/sessions/{id}
#
# Throws on failed sessions; prompts the operator on Warning outcomes.

function Invoke-AutomationSession {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $Endpoint,
        [Parameter(Mandatory)] [object]         $Body,
        [ValidateSet('Post', 'Put')]
        [string] $Method = 'Post',
        [int]    $PollIntervalSeconds = 5,
        [int]    $TimeoutSeconds      = 300,
        [switch] $Quiet
    )

    $uri      = "$($Connection.BaseUri)$Endpoint"
    $bodyJson = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }

    try {
        $response = Invoke-RestMethod -Uri $uri -Method $Method `
            -Headers $Connection.Headers `
            -Body $bodyJson `
            -SkipCertificateCheck
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $details    = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        $details    = Format-RedactedJson -Text $details
        throw "Automation request failed (HTTP $statusCode).`n  URL: $uri`n  Response: $details"
    }

    # When the response carries id + state, treat it as an async session and poll.
    if (-not [string]::IsNullOrEmpty($response.id) -and $null -ne $response.state) {
        $sessionId = $response.id
        $statusUri = if ($response.sessionType -eq 'Automation') {
            "$($Connection.BaseUri)/automation/sessions/$sessionId"
        } else {
            "$($Connection.BaseUri)/sessions/$sessionId"
        }
        $deadline  = (Get-Date).AddSeconds($TimeoutSeconds)

        if (-not $Quiet) {
            Write-Host "  Session $sessionId started — polling every ${PollIntervalSeconds}s"
        }

        do {
            Start-Sleep -Seconds $PollIntervalSeconds

            try {
                $status = Invoke-RestMethod -Uri $statusUri -Method Get `
                    -Headers $Connection.Headers -SkipCertificateCheck
            } catch {
                throw "Failed to poll session status.`n  URL: $statusUri`n  Error: $($_.Exception.Message)"
            }

            if (-not $Quiet) {
                Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] State: $($status.state)"
            }

            if ((Get-Date) -gt $deadline) {
                throw "Session $sessionId timed out after $TimeoutSeconds seconds."
            }
        } while ($status.state -in @('Working', 'Running'))

        # Veeam sessions reach state 'Stopped' regardless of outcome. The actual
        # success/failure is in $status.result.result.
        $resultStatus = $status.result.result
        $resultMsg    = $status.result.message

        if ($resultStatus -eq 'Failed') {
            try {
                $logs    = Invoke-RestMethod -Uri "$statusUri/logs" -Method Get `
                    -Headers $Connection.Headers -SkipCertificateCheck
                $logText = $logs | ConvertTo-Json -Depth 5
            } catch {
                $logText = "(could not retrieve logs: $($_.Exception.Message))"
            }
            throw "Session $sessionId failed: $resultMsg`nLogs:`n$logText"
        }

        if ($resultStatus -eq 'Warning') {
            Write-Warning "Session $sessionId completed with a warning: $resultMsg"
            $answer = Read-Host "Continue despite the warning? [y/N]"
            if ([string]::IsNullOrWhiteSpace($answer) -or $answer -notmatch '^[Yy]') {
                throw "Cancelled by user after session warning."
            }
        }

        return $status
    }

    # No session — synchronous response, return as-is.
    return $response
}

# Get-VBRPaginatedData
# Fetches all pages from a paginated Veeam REST API GET endpoint. Returns a
# flat array of every item across all pages. Used by callers that need a
# complete list without manually iterating the pagination cursor.

function Get-VBRPaginatedData {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Connection,
        [Parameter(Mandatory)] [string]         $Endpoint,
        [int] $PageSize = 100
    )

    $all  = [System.Collections.Generic.List[object]]::new()
    $skip = 0

    do {
        $uri = "$($Connection.BaseUri)${Endpoint}?skip=$skip&limit=$PageSize"

        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get `
                -Headers $Connection.Headers -SkipCertificateCheck
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            throw "GET failed (HTTP $statusCode).`n  URL: $uri`n  Error: $($_.Exception.Message)"
        }

        $page = @($response.data)
        foreach ($item in $page) { $all.Add($item) }

        $skip += $PageSize
    } while ($page.Count -gt 0 -and $all.Count -lt $response.pagination.total)

    return $all.ToArray()
}

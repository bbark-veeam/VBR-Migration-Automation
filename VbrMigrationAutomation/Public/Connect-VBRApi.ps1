# Connect-VBRApi
# Authenticates against the Veeam Backup & Replication REST API and returns a
# connection object that other module functions use to make subsequent calls.
# The returned object carries the BaseUri (with the /api/v1 prefix), the raw
# bearer AccessToken, and a Headers hashtable suitable for direct use with
# Invoke-RestMethod calls against the API, including the x-api-version
# header (REST API 1.3-rev2, VBR 13.x) that every request must carry.

function Connect-VBRApi {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [PSCredential] $Credential,
        [int]    $Port       = 9419,
        [string] $ApiVersion = '1.3-rev2'
    )

    $uri = "https://$($Server):$Port/api/oauth2/token"

    $body = @{
        grant_type = 'password'
        username   = $Credential.UserName
        password   = $Credential.GetNetworkCredential().Password
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body `
        -Headers @{ 'x-api-version' = $ApiVersion } `
        -ContentType 'application/x-www-form-urlencoded' `
        -SkipCertificateCheck `
        -ErrorAction Stop

    return [PSCustomObject]@{
        BaseUri     = "https://$($Server):$Port/api/v1"
        AccessToken = $response.access_token
        Headers     = @{
            Authorization   = "Bearer $($response.access_token)"
            'Content-Type'  = 'application/json'
            Accept          = 'application/json'
            'x-api-version' = $ApiVersion
        }
    }
}

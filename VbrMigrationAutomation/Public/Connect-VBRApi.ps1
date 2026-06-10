# Connect-VBRApi
# Authenticates against the Veeam Backup & Replication REST API and returns a
# connection object that other module functions use to make subsequent calls.
# The returned object carries the BaseUri (with the /api/v1 prefix), the raw
# bearer AccessToken, and a Headers hashtable suitable for direct use with
# Invoke-RestMethod calls against the API.

function Connect-VBRApi {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [PSCredential] $Credential,
        [int] $Port = 9419
    )

    $uri = "https://$($Server):$Port/api/oauth2/token"

    $body = @{
        grant_type = 'password'
        username   = $Credential.UserName
        password   = $Credential.GetNetworkCredential().Password
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body `
        -ContentType 'application/x-www-form-urlencoded' `
        -SkipCertificateCheck `
        -ErrorAction Stop

    return [PSCustomObject]@{
        BaseUri     = "https://$($Server):$Port/api/v1"
        AccessToken = $response.access_token
        Headers     = @{
            Authorization  = "Bearer $($response.access_token)"
            'Content-Type' = 'application/json'
            Accept         = 'application/json'
        }
    }
}

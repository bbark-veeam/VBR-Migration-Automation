# Get-VBRPaginatedData.Tests.ps1
# Unit tests for the paging helper used by every list lookup on the target.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Get-VBRPaginatedData.ps1')
    $script:conn = [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }
}

Describe 'Get-VBRPaginatedData' {
    It 'reads every page until the reported total is reached' {
        Mock Invoke-RestMethod {
            $skip = [int]([regex]::Match($Uri, 'skip=(\d+)').Groups[1].Value)
            $items = @($skip..([Math]::Min($skip + 1, 4)) | ForEach-Object { [pscustomobject]@{ n = $_ } })
            [pscustomobject]@{ data = $items; pagination = [pscustomobject]@{ total = 5 } }
        }
        $all = @(Get-VBRPaginatedData -Connection $conn -Endpoint '/credentials' -PageSize 2)
        ($all | ForEach-Object n) -join ',' | Should -Be '0,1,2,3,4'
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
    }

    It 'stops on an empty page even if the total says there are more' {
        Mock Invoke-RestMethod { [pscustomobject]@{ data = @(); pagination = [pscustomobject]@{ total = 10 } } }
        @(Get-VBRPaginatedData -Connection $conn -Endpoint '/credentials').Count | Should -Be 0
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'returns a single page when the response has no pagination block' {
        Mock Invoke-RestMethod { [pscustomobject]@{ data = @([pscustomobject]@{ n = 1 }) } }
        @(Get-VBRPaginatedData -Connection $conn -Endpoint '/x').Count | Should -Be 1
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'throws with the URL when a request fails' {
        Mock Invoke-RestMethod { throw 'boom' }
        { Get-VBRPaginatedData -Connection $conn -Endpoint '/credentials' } | Should -Throw -ExpectedMessage '*/credentials?skip=0&limit=100*'
    }
}

# Test-VBRVsaWindowsCredential.Tests.ps1
# Unit tests for the VSA Windows-credential format checks. REST calls and
# Read-Host are mocked; export files are written to TestDrive.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Test-VBRVsaWindowsCredential.ps1')
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Format-RedactedJson.ps1')
    function Get-VBRPaginatedData { param($Connection, $Endpoint) }

    function New-Conn([string] $Platform) {
        [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{}; ServerPlatform = $Platform }
    }

    function New-Export([string] $HostUser, [string[]] $ExportedUsers) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        @{ windowsHosts = @(@{ type = 'WindowsHost'; name = 'Repo-01.lab.local'
                               credentials = @{ credentialsName = $HostUser; credentialsTag = 'old-tag' } })
           linuxHosts = @(); viHosts = @(); cloudDirectorHosts = @() } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'ManagedServers.json')
        @{ credentials = @($ExportedUsers | ForEach-Object { @{ username = $_; uniqueId = [guid]::NewGuid() } }) } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'Credentials.json')
        $dir
    }
}

Describe 'Test-VBRVsaCredentialFormat' {
    It 'accepts <u>' -ForEach @(
        @{ u = 'administrator@lab.local' }
        @{ u = 'svc.veeam@corp.example.com' }
        @{ u = 'lab.local\administrator' }
        @{ u = 'corp.example.com\svc-veeam' }
    ) { Test-VBRVsaCredentialFormat $u | Should -BeTrue }

    It 'rejects <u>' -ForEach @(
        @{ u = 'contoso\administrator' }
        @{ u = 'VBR-SRC01\Administrator' }
        @{ u = 'administrator' }
        @{ u = 'root' }
        @{ u = 'admin@localhost' }
        @{ u = '' }
    ) { Test-VBRVsaCredentialFormat $u | Should -BeFalse }
}

Describe 'Get-VBRServerPlatform' {
    It 'reads /serverInfo once and caches the platform on the connection' {
        Mock Invoke-RestMethod { [pscustomobject]@{ platform = 'Linux' } }
        $c = [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }
        Get-VBRServerPlatform -Connection $c | Should -Be 'Linux'
        Get-VBRServerPlatform -Connection $c | Should -Be 'Linux'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://t/api/v1/serverInfo' }
    }
}

Describe 'Test-VBRVsaWindowsCredential' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-VBRPaginatedData { @() } -ParameterFilter { $Endpoint -like '*managedServers' }
    }

    It 'does nothing on a Windows target' {
        Mock Get-VBRPaginatedData { throw 'should not be called' }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Windows') -InputPath (New-Export 'lab\admin' @()) } |
            Should -Not -Throw
    }

    It 'passes on a VSA when every Windows host already uses UPN or FQDN\user' {
        Mock Get-VBRPaginatedData { throw 'should not be called' }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'admin@lab.local' @()) } |
            Should -Not -Throw
    }

    It 'ignores Windows hosts that are already on the target' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'repo-01.lab.local' }) } -ParameterFilter { $Endpoint -like '*managedServers' }
        Mock Get-VBRPaginatedData { throw 'credentials should not be checked' } -ParameterFilter { $Endpoint -eq '/credentials' }
        Mock Read-Host { throw 'should not prompt' }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin')) } |
            Should -Not -Throw
    }

    It 'continues when an accepted credential exists in the export' {
        Mock Get-VBRPaginatedData { @() }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin', 'admin@lab.local')) } |
            Should -Not -Throw
    }

    It 'continues when an accepted credential exists only on the target' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ username = 'lab.local\admin' }) }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin')) } |
            Should -Not -Throw
    }

    It 'aborts on Q when no accepted credential exists anywhere' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ username = 'root' }) }
        Mock Read-Host { 'Q' }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin')) } |
            Should -Throw -ExpectedMessage '*aborted*Nothing has been imported*'
    }

    It 'option 2 waits, then continues once the credential has been added on the VSA' {
        $script:calls = 0
        Mock Get-VBRPaginatedData {
            $script:calls++
            if ($script:calls -eq 1) { @([pscustomobject]@{ username = 'root' }) }
            else { @([pscustomobject]@{ username = 'admin@lab.local' }) }
        }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('2', ''))
        Mock Read-Host { $script:answers.Dequeue() }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin')) } |
            Should -Not -Throw
        Should -Invoke Read-Host -Times 2 -Exactly
    }

    It 'option 1 creates the credential on the target, then continues' {
        $script:created = $false
        Mock Get-VBRPaginatedData {
            if ($script:created) { @([pscustomobject]@{ username = 'admin@lab.local' }) } else { @() }
        }
        Mock Invoke-RestMethod { $script:created = $true; [pscustomobject]@{ username = 'admin@lab.local'; uniqueId = 'new' } } `
            -ParameterFilter { $Method -eq 'Post' }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('1', 'lab\admin', 'admin@lab.local'))
        Mock Read-Host { $script:answers.Dequeue() } -ParameterFilter { -not $AsSecureString }
        Mock Read-Host {
            $secure = [System.Security.SecureString]::new()
            foreach ($ch in 'test-value'.ToCharArray()) { $secure.AppendChar($ch) }
            $secure
        } -ParameterFilter { $AsSecureString }

        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin')) } |
            Should -Not -Throw
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Uri -eq 'https://t/api/v1/credentials' -and
            ($Body | ConvertFrom-Json).username -eq 'admin@lab.local' -and ($Body | ConvertFrom-Json).type -eq 'Standard'
        }
    }

    It 'option 1 returns to the menu without creating anything when the user name is left blank' {
        Mock Get-VBRPaginatedData { @() }
        Mock Invoke-RestMethod { throw 'should not create' }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('1', '', 'q'))
        Mock Read-Host { $script:answers.Dequeue() }
        { Test-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -InputPath (New-Export 'lab\admin' @('lab\admin')) } |
            Should -Throw -ExpectedMessage '*aborted*'
    }
}

Describe 'Resolve-VBRVsaWindowsCredential' {
    BeforeEach {
        Mock Write-Host { }
        $script:payload = [pscustomobject]@{ windowsHosts = @(
            [pscustomobject]@{ name = 'Repo-01.lab.local'
                               credentials = [pscustomobject]@{ credentialsName = 'lab\admin'; credentialsTag = 'old-tag' } }
            [pscustomobject]@{ name = 'ok.lab.local'
                               credentials = [pscustomobject]@{ credentialsName = 'svc@lab.local'; credentialsTag = 'keep' } }) }
        Mock Get-VBRPaginatedData {
            @([pscustomobject]@{ username = 'lab\admin';       uniqueId = 'u-netbios'; description = '' }
              [pscustomobject]@{ username = 'admin@lab.local'; uniqueId = 'u-upn';     description = 'UPN' })
        }
    }

    It 'replaces only the non-compliant credential with the chosen accepted one' {
        Mock Read-Host { '1' }
        Resolve-VBRVsaWindowsCredential -Connection (New-Conn 'Linux') -Payload $payload
        $payload.windowsHosts[0].credentials.credentialsName | Should -Be 'admin@lab.local'
        $payload.windowsHosts[0].credentials.credentialsTag  | Should -Be 'u-upn'
        $payload.windowsHosts[1].credentials.credentialsTag  | Should -Be 'keep'
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'leaves the payload alone on a Windows target' {
        Mock Read-Host { throw 'should not prompt' }
        Resolve-VBRVsaWindowsCredential -Connection (New-Conn 'Windows') -Payload $payload
        $payload.windowsHosts[0].credentials.credentialsTag | Should -Be 'old-tag'
    }
}

Describe 'Select-VBRVsaCredential' {
    BeforeEach { Mock Write-Host { } }

    It 'returns an existing accepted credential by number, listing only accepted forms' {
        Mock Get-VBRPaginatedData {
            @([pscustomobject]@{ username = 'lab\admin';       uniqueId = 'u-netbios' }
              [pscustomobject]@{ username = 'admin@lab.local'; uniqueId = 'u-upn' })
        }
        Mock Read-Host { '1' }
        (Select-VBRVsaCredential -Connection (New-Conn 'Linux') -HostName 'h').uniqueId | Should -Be 'u-upn'
        Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*lab\admin*' }
    }

    It 'N creates a new credential even when accepted ones already exist, and returns it' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ username = 'old@lab.local'; uniqueId = 'u-old' }) }
        Mock Invoke-RestMethod { [pscustomobject]@{ username = 'svc@acquired.example.com'; uniqueId = 'u-new' } } `
            -ParameterFilter { $Method -eq 'Post' }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('N', 'svc@acquired.example.com'))
        Mock Read-Host { $script:answers.Dequeue() } -ParameterFilter { -not $AsSecureString }
        Mock Read-Host {
            $secure = [System.Security.SecureString]::new()
            foreach ($ch in 'test-value'.ToCharArray()) { $secure.AppendChar($ch) }
            $secure
        } -ParameterFilter { $AsSecureString }

        (Select-VBRVsaCredential -Connection (New-Conn 'Linux') -HostName 'h').uniqueId | Should -Be 'u-new'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'Post' }
    }

    It 'M waits, refreshes the list, and offers a credential added on the VSA' {
        $script:calls = 0
        Mock Get-VBRPaginatedData {
            $script:calls++
            if ($script:calls -eq 1) { @([pscustomobject]@{ username = 'old@lab.local'; uniqueId = 'u-old' }) }
            else { @([pscustomobject]@{ username = 'old@lab.local'; uniqueId = 'u-old' }
                     [pscustomobject]@{ username = 'svc@acquired.example.com'; uniqueId = 'u-console' }) }
        }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('m', '', '2'))
        Mock Read-Host { $script:answers.Dequeue() }
        (Select-VBRVsaCredential -Connection (New-Conn 'Linux') -HostName 'h').uniqueId | Should -Be 'u-console'
        Should -Invoke Get-VBRPaginatedData -Times 2 -Exactly
    }

    It 'Q aborts, naming the host' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ username = 'old@lab.local'; uniqueId = 'u-old' }) }
        Mock Read-Host { 'q' }
        { Select-VBRVsaCredential -Connection (New-Conn 'Linux') -HostName 'Repo-01.lab.local' } |
            Should -Throw -ExpectedMessage "*aborted*Repo-01.lab.local*"
    }

    It 'still offers N, M and Q when no accepted credential exists' {
        Mock Get-VBRPaginatedData { @() }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('1', 'Q'))
        Mock Read-Host { $script:answers.Dequeue() }
        { Select-VBRVsaCredential -Connection (New-Conn 'Linux') -HostName 'h' } | Should -Throw -ExpectedMessage '*aborted*'
        Should -Invoke Read-Host -Times 2 -Exactly
    }
}

# Test-VBRPairedApplianceHost.Tests.ps1
# Unit tests for the certificate-paired appliance pre-check. Export files are
# written to TestDrive; the target's managed-server list is mocked.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Test-VBRPairedApplianceHost.ps1')
    function Get-VBRPaginatedData { param($Connection, $Endpoint) }
    $script:conn = [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }

    function New-Export([object[]] $LinuxHosts) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        @{ windowsHosts = @(@{ type = 'WindowsHost'; name = 'Repo-01.lab.local'
                               credentials = @{ credentialsName = 'lab\admin'; credentialsTag = 'c1' } })
           linuxHosts = $LinuxHosts; viHosts = @(); cloudDirectorHosts = @() } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'ManagedServers.json')
        @{ WindowsLocalRepositories  = @(@{ name = 'Repo-01'; hostName = 'Repo-01.lab.local' })
           LinuxHardenedRepositories = @(@{ name = 'Hardened Repo'; hostName = 'Repo.lab.local' }) } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'Repositories.json')
        $dir
    }

    $script:appliance  = @{ type = 'LinuxHost'; name = 'Repo.lab.local'
                            sshSettings = @{ portRangeStart = 2500; portRangeEnd = 3300 } }
    $script:sshHost    = @{ type = 'LinuxHost'; name = 'linux-proxy.lab.local'; sshFingerprint = 'ssh-rsa AAAA'
                            credentials = @{ credentialsName = 'root'; credentialsTag = 'c2' } }
}

Describe 'Get-VBRPairedApplianceHost' {
    It 'flags a Linux host with no credentials and no SSH fingerprint, with its repositories' {
        $found = @(Get-VBRPairedApplianceHost -InputPath (New-Export @($appliance, $sshHost)))
        $found.Count           | Should -Be 1
        $found[0].Name         | Should -Be 'Repo.lab.local'
        $found[0].Repositories | Should -Be @('Hardened Repo')
    }

    It 'ignores Linux hosts added with credentials and a fingerprint' {
        @(Get-VBRPairedApplianceHost -InputPath (New-Export @($sshHost))).Count | Should -Be 0
    }
}

Describe 'Test-VBRPairedApplianceHost' {
    BeforeEach { Mock Write-Host { }; Mock Write-Warning { } }

    It 'waits for pairing, re-checks on Enter, and continues once the appliance is on the target' {
        $script:calls = 0
        Mock Get-VBRPaginatedData {
            $script:calls++
            if ($script:calls -eq 1) { @([pscustomobject]@{ name = 'vbr.lab.local' }) }
            else { @([pscustomobject]@{ name = 'vbr.lab.local' }, [pscustomobject]@{ name = 'Repo.lab.local' }) }
        }
        Mock Read-Host { '' }
        { Test-VBRPairedApplianceHost -Connection $conn -InputPath (New-Export @($appliance)) -TargetVBR 'vbr.lab.local' } |
            Should -Not -Throw
        Should -Invoke Read-Host -Times 1 -Exactly
        Should -Invoke Get-VBRPaginatedData -Times 2 -Exactly
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Repo.lab.local*Hardened Repo*' }
    }

    It 'keeps waiting while the appliance is still missing' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'vbr.lab.local' }) }
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('', '', 'q'))
        Mock Read-Host { $script:answers.Dequeue() }
        { Test-VBRPairedApplianceHost -Connection $conn -InputPath (New-Export @($appliance)) } | Should -Throw
        Should -Invoke Read-Host -Times 3 -Exactly
    }

    It 'aborts on Q without importing, naming the host' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'vbr.lab.local' }) }
        Mock Read-Host { 'Q' }
        { Test-VBRPairedApplianceHost -Connection $conn -InputPath (New-Export @($appliance)) } |
            Should -Throw -ExpectedMessage '*aborted*Repo.lab.local*Nothing has been imported*'
    }

    It 'passes without prompting when the appliance is already paired under the same name' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'Repo.lab.local' }) }
        Mock Read-Host { throw 'should not prompt' }
        { Test-VBRPairedApplianceHost -Connection $conn -InputPath (New-Export @($appliance)) } | Should -Not -Throw
        Should -Invoke Write-Warning -Times 0
    }

    It 'warns, without stopping, when the name differs only in case' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'repo.lab.local' }) }
        Mock Read-Host { throw 'should not prompt' }
        { Test-VBRPairedApplianceHost -Connection $conn -InputPath (New-Export @($appliance)) } | Should -Not -Throw
        Should -Invoke Write-Warning -Times 1
    }

    It 'does not query the target when the export has no appliances' {
        Mock Get-VBRPaginatedData { throw 'should not be called' }
        { Test-VBRPairedApplianceHost -Connection $conn -InputPath (New-Export @($sshHost)) } | Should -Not -Throw
    }
}

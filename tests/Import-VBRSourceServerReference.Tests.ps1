# Import-VBRSourceServerReference.Tests.ps1
# Which repository host references lead to adding a managed server on the
# target: re-run safety, repositories skipped by name, mount servers on the
# Source Veeam Server (remapped elsewhere), and the source-console warning.

BeforeAll {
    $root = Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation'
    . (Join-Path $root 'Public' 'Import-VBRSourceServerReference.ps1')
    function Get-VBRPaginatedData { param($Connection, $Endpoint) }
    function Get-VBRServerPlatform { param($Connection) 'Windows' }
    function Invoke-AutomationSession { param($Connection, $Endpoint, $Body, [switch]$Quiet) }
    $script:conn = [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }

    function New-Export([object[]] $Repos) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        @{ WindowsLocalRepositories = $Repos } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'Repositories.json')
        @{ windowsHosts = @(); linuxHosts = @(); viHosts = @(); cloudDirectorHosts = @() } |
            ConvertTo-Json | Set-Content (Join-Path $dir 'ManagedServers.json')
        $dir
    }

    $script:onSource = @{ name = 'Source Local Repo'; hostName = 'VBR-Src01.lab.local'
                          mountServer = @{ windows = @{ mountServerName = 'VBR-Src01.lab.local' } } }
    $script:mountOnly = @{ name = 'Hardened Repo'; hostName = 'Repo.lab.local'
                           mountServer = @{ windows = @{ mountServerName = 'VBR-Src01.lab.local' } } }
}

Describe 'Import-VBRSourceServerReference' {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Warning { }
        Mock Invoke-AutomationSession { }
        Mock Get-VBRPaginatedData { @() } -ParameterFilter { $Endpoint -like '*repositories' }
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'Repo.lab.local' }) } -ParameterFilter { $Endpoint -like '*managedServers' }
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ username = 'lab\admin'; uniqueId = 'c1' }) } -ParameterFilter { $Endpoint -eq '/credentials' }
        Mock Read-Host { '1' }
    }

    It 'does not add the source VBR when it is only a mount server (remapped to the target)' {
        Mock Read-Host { throw 'should not prompt' }
        Import-VBRSourceServerReference -Connection $conn -InputPath (New-Export @($mountOnly)) -SourceVBR 'VBR-Src01.lab.local'
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'ignores repositories whose name is already on the target' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'source local repo' }) } -ParameterFilter { $Endpoint -like '*repositories' }
        Mock Read-Host { throw 'should not prompt' }
        Import-VBRSourceServerReference -Connection $conn -InputPath (New-Export @($onSource)) -SourceVBR 'VBR-Src01.lab.local'
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'skips a referenced host that is already a managed server on the target (any case)' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'vbr-src01.lab.local' }) } -ParameterFilter { $Endpoint -like '*managedServers' }
        Mock Read-Host { throw 'should not prompt' }
        Import-VBRSourceServerReference -Connection $conn -InputPath (New-Export @($onSource)) -SourceVBR 'VBR-Src01.lab.local'
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'adds the source VBR when it hosts a repository being imported, and warns about removing it later' {
        Import-VBRSourceServerReference -Connection $conn -InputPath (New-Export @($onSource)) -SourceVBR 'VBR-Src01.lab.local'
        Should -Invoke Invoke-AutomationSession -Times 1 -ParameterFilter { $Endpoint -eq '/automation/managedServers/import' }
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*Source Local Repo*' }
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*uninstalls Veeam components*' }
    }
}

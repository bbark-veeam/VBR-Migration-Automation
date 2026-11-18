# Import-VBRSourceServerReference.Tests.ps1
# Re-run safety: hosts referenced by repositories that already exist on the
# target are not added again.

BeforeAll {
    $root = Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation'
    . (Join-Path $root 'Public' 'Import-VBRSourceServerReference.ps1')
    function Get-VBRPaginatedData { param($Connection, $Endpoint) }
    function Get-VBRServerPlatform { param($Connection) 'Windows' }
    function Invoke-AutomationSession { param($Connection, $Endpoint, $Body, [switch]$Quiet) }
    $script:conn = [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }

    function New-Export {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        @{ WindowsLocalRepositories = @(@{ name = 'Default Backup Repository'; hostName = 'Win-VBR.lab.local'
                                           mountServer = @{ windows = @{ mountServerName = 'Win-VBR.lab.local' } } }) } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'Repositories.json')
        @{ windowsHosts = @(); linuxHosts = @(); viHosts = @(); cloudDirectorHosts = @() } |
            ConvertTo-Json | Set-Content (Join-Path $dir 'ManagedServers.json')
        $dir
    }
}

Describe 'Import-VBRSourceServerReference' {
    BeforeEach { Mock Write-Host { }; Mock Invoke-AutomationSession { } }

    It 'skips a referenced host that is already a managed server on the target (any case)' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'win-vbr.lab.local' }) }
        Mock Invoke-RestMethod { throw 'should not list credentials' }
        Mock Read-Host { throw 'should not prompt' }
        Import-VBRSourceServerReference -Connection $conn -InputPath (New-Export)
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'still offers to add a referenced host that is not on the target' {
        Mock Get-VBRPaginatedData { @([pscustomobject]@{ name = 'other.lab.local' }) }
        Mock Invoke-RestMethod { [pscustomobject]@{ data = @([pscustomobject]@{ username = 'lab\admin'; uniqueId = 'c1' }) } }
        Mock Read-Host { '1' }
        Import-VBRSourceServerReference -Connection $conn -InputPath (New-Export)
        Should -Invoke Invoke-AutomationSession -Times 1 -ParameterFilter { $Endpoint -eq '/automation/managedServers/import' }
    }
}

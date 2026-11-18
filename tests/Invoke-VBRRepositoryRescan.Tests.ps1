# Invoke-VBRRepositoryRescan.Tests.ps1
# Unit tests for the post-import repository rescan offer. REST helpers and
# Read-Host are mocked.

BeforeAll {
    $private = Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private'
    . (Join-Path $private 'Invoke-VBRRepositoryRescan.ps1')
    function Get-VBRPaginatedData { param($Connection, $Endpoint) }
    function Invoke-AutomationSession { param($Connection, $Endpoint, $Body, $TimeoutSeconds, [switch]$Quiet) }
    $script:conn = [pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }
}

Describe 'Invoke-VBRRepositoryRescan' {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Warning { }
        Mock Get-VBRPaginatedData {
            @([pscustomobject]@{ name = 'Default Backup Repository'; id = 'id-default' },
              [pscustomobject]@{ name = 'Win-Repo'; id = 'id-winrepo' })
        }
        Mock Invoke-AutomationSession { }
    }

    It 'does nothing when no repositories were imported' {
        Mock Read-Host { throw 'should not prompt' }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @()
        Should -Invoke Get-VBRPaginatedData -Times 0
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'rescans only the imported repositories when the operator answers y' {
        Mock Read-Host { 'y' }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('win-repo')
        Should -Invoke Invoke-AutomationSession -Times 1 -ParameterFilter {
            $Endpoint -eq '/backupInfrastructure/repositories/rescan' -and
            (@($Body.repositoryIds) -join ',') -eq 'id-winrepo'
        }
    }

    It 'skips the rescan by default (Enter) and on n' -ForEach @(@{ A = '' }, @{ A = 'n' }) {
        Mock Read-Host { $A }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('Win-Repo')
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'skips without prompting when none of the names exist on the target' {
        Mock Read-Host { throw 'should not prompt' }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('Missing-Repo')
        Should -Invoke Invoke-AutomationSession -Times 0
        Should -Invoke Write-Warning -Times 1
    }

    It 'warns instead of throwing when the rescan fails' {
        Mock Read-Host { 'y' }
        Mock Invoke-AutomationSession { throw 'HTTP 404' }
        { Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('Win-Repo') } | Should -Not -Throw
        Should -Invoke Write-Warning -Times 2
    }
}

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
              [pscustomobject]@{ name = 'Repo-01'; id = 'id-repo01' })
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
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('repo-01')
        Should -Invoke Invoke-AutomationSession -Times 1 -ParameterFilter {
            $Endpoint -eq '/backupInfrastructure/repositories/rescan' -and
            (@($Body.repositoryIds) -join ',') -eq 'id-repo01'
        }
    }

    It 'skips the rescan by default (Enter) and on n' -ForEach @(@{ A = '' }, @{ A = 'n' }) {
        Mock Read-Host { $A }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('Repo-01')
        Should -Invoke Invoke-AutomationSession -Times 0
    }

    It 'lists repositories already on the target without offering them, and offers only new ones' {
        Mock Read-Host { 'y' }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('Repo-01') -ExistingRepositoryNames @('Default Backup Repository')
        Should -Invoke Read-Host -Times 1 -Exactly
        Should -Invoke Invoke-AutomationSession -Times 1 -ParameterFilter { (@($Body.repositoryIds) -join ',') -eq 'id-repo01' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Not offered for rescan*Default Backup Repository*' }
    }

    It 'only notes existing repositories on a re-run where nothing was imported' {
        Mock Read-Host { throw 'should not prompt' }
        Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @() -ExistingRepositoryNames @('Repo-01', 'Hardened Repo')
        Should -Invoke Invoke-AutomationSession -Times 0
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Not offered for rescan*Repo-01, Hardened Repo*' }
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
        { Invoke-VBRRepositoryRescan -Connection $conn -RepositoryNames @('Repo-01') } | Should -Not -Throw
        Should -Invoke Write-Warning -Times 2
    }
}

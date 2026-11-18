# Update-VBRJobRepositoryId.Tests.ps1
# Unit tests for mapping agent-job repository IDs from source to target.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Update-VBRJobRepositoryId.ps1')

    function New-Export {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        @{ LinuxHardenedRepositories = @(@{ name = 'Hardened Repo'; uniqueId = '0073598F5E6F404CB3FCE0026C727F83' })
           WindowsLocalRepositories  = @(@{ name = 'Gone Repo';     uniqueId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' }) } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'Repositories.json')
        $dir
    }

    function New-Job {
        @'
{ "name": "AD Protection Group Job",
  "storage": { "backupRepositoryId": "0073598f-5e6f-404c-b3fc-e0026c727f83" },
  "policy":  { "storage": { "destination": { "backupRepositoryId": "0073598f-5e6f-404c-b3fc-e0026c727f83" } } } }
'@ | ConvertFrom-Json -Depth 10
    }
}

Describe 'Update-VBRJobRepositoryId' {
    It 'maps the source ID to the same-named repository on the target, wherever it appears' {
        $resolver = New-VBRRepositoryIdResolver -InputPath (New-Export) -TargetRepositories @(
            [pscustomobject]@{ id = '11111111-2222-3333-4444-555555555555'; name = 'Hardened Repo' })
        $job = New-Job
        Update-VBRJobRepositoryId -Job $job -Resolver $resolver | Should -BeNullOrEmpty
        $job.storage.backupRepositoryId                            | Should -Be '11111111-2222-3333-4444-555555555555'
        $job.policy.storage.destination.backupRepositoryId         | Should -Be '11111111-2222-3333-4444-555555555555'
    }

    It 'keeps an ID that already exists on the target' {
        $resolver = New-VBRRepositoryIdResolver -InputPath (New-Export) -TargetRepositories @(
            [pscustomobject]@{ id = '0073598f-5e6f-404c-b3fc-e0026c727f83'; name = 'Renamed' })
        $job = New-Job
        Update-VBRJobRepositoryId -Job $job -Resolver $resolver | Should -BeNullOrEmpty
        $job.storage.backupRepositoryId | Should -Be '0073598f-5e6f-404c-b3fc-e0026c727f83'
    }

    It 'reports a repository that is not on the target, with its source name' {
        $resolver = New-VBRRepositoryIdResolver -InputPath (New-Export) -TargetRepositories @(
            [pscustomobject]@{ id = 'x'; name = 'Other' })
        $bad = @(Update-VBRJobRepositoryId -Job (New-Job) -Resolver $resolver)
        $bad.Count | Should -Be 2
        $bad[0]    | Should -BeLike "*'Hardened Repo'*"
    }

    It 'ignores the empty GUID' {
        $resolver = New-VBRRepositoryIdResolver -InputPath (New-Export) -TargetRepositories @()
        $job = [pscustomobject]@{ storage = [pscustomobject]@{ backupRepositoryId = '00000000-0000-0000-0000-000000000000' } }
        Update-VBRJobRepositoryId -Job $job -Resolver $resolver | Should -BeNullOrEmpty
    }
}

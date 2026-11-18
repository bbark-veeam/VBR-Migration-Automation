# Get-VBRDefaultExportPath.Tests.ps1
# Unit tests for the private Get-VBRDefaultExportPath helper. Dot-sourced
# directly so the tests run without the module having to be loaded.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Get-VBRDefaultExportPath.ps1')
}

Describe 'Get-VBRDefaultExportPath' {
    It 'names the folder server_yyyy-MM-dd_HHmmss under output' {
        $ts     = [datetime]'2026-11-18T08:02:35'
        $result = Get-VBRDefaultExportPath -Server 'PG-Upgrade-Test.HackShack.local' -Timestamp $ts
        $expect = Join-Path (Join-Path (Get-Location).Path 'output') 'PG-Upgrade-Test.HackShack.local_2026-11-18_080235'
        $result | Should -Be $expect
    }

    It 'replaces characters that are invalid in folder names' {
        $result = Get-VBRDefaultExportPath -Server 'fe80::1' -Timestamp ([datetime]'2026-01-02T03:04:05')
        Split-Path $result -Leaf | Should -Be 'fe80__1_2026-01-02_030405'
    }

    It 'returns a different folder for a different timestamp' {
        $a = Get-VBRDefaultExportPath -Server 'vbr01' -Timestamp ([datetime]'2026-11-18T08:00:00')
        $b = Get-VBRDefaultExportPath -Server 'vbr01' -Timestamp ([datetime]'2026-11-18T08:00:01')
        $a | Should -Not -Be $b
    }
}

# Resolve-VBRImportPath.Tests.ps1
# Unit tests for the private Resolve-VBRImportPath helper. Dot-sourced
# directly; Read-Host is mocked for the multi-export prompt.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Resolve-VBRImportPath.ps1')

    function New-TestExport([string] $Root, [string] $Name, [string] $Server, [string] $Timestamp) {
        $dir = Join-Path $Root $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        @{ sourceServer = $Server; isVSA = $false; exportTimestamp = $Timestamp } |
            ConvertTo-Json | Set-Content (Join-Path $dir '_metadata.json')
        $dir
    }
}

Describe 'Resolve-VBRImportPath' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $root | Out-Null
        Mock Write-Host { }
    }

    It 'returns an explicit -InputPath unchanged without looking at output' {
        Mock Read-Host { throw 'should not prompt' }
        Resolve-VBRImportPath -InputPath 'C:\somewhere' -OutputRoot $root | Should -Be 'C:\somewhere'
    }

    It 'throws when the output root does not exist' {
        { Resolve-VBRImportPath -OutputRoot (Join-Path $root 'missing') } | Should -Throw '*does not exist*'
    }

    It 'throws when no folder holds a _metadata.json' {
        New-Item -ItemType Directory -Path (Join-Path $root 'not-an-export') | Out-Null
        { Resolve-VBRImportPath -OutputRoot $root } | Should -Throw '*No export folders*'
    }

    It 'uses the only export without prompting' {
        Mock Read-Host { throw 'should not prompt' }
        $only = New-TestExport $root 'vbr01_2026-11-18_080235' 'vbr01' '2026-11-18T08:02:35-08:00'
        New-Item -ItemType Directory -Path (Join-Path $root 'P05') | Out-Null
        Resolve-VBRImportPath -OutputRoot $root | Should -Be (Get-Item $only).FullName
    }

    It 'accepts a legacy flat export in the output root itself' {
        Mock Read-Host { throw 'should not prompt' }
        @{ sourceServer = 'old'; exportTimestamp = '2026-06-01T00:00:00Z' } |
            ConvertTo-Json | Set-Content (Join-Path $root '_metadata.json')
        Resolve-VBRImportPath -OutputRoot $root | Should -Be (Get-Item $root).FullName
    }

    It 'lists several exports newest first and returns the chosen one' {
        $old = New-TestExport $root 'a_old' 'vbr-a' '2026-11-01T10:00:00-08:00'
        $new = New-TestExport $root 'b_new' 'vbr-b' '2026-11-18T10:00:00-08:00'
        Mock Read-Host { '2' }
        Resolve-VBRImportPath -OutputRoot $root | Should -Be (Get-Item $old).FullName
        Mock Read-Host { '1' }
        Resolve-VBRImportPath -OutputRoot $root | Should -Be (Get-Item $new).FullName
    }

    It 're-prompts until the answer is a number in range' {
        New-TestExport $root 'a' 'vbr-a' '2026-11-01T10:00:00Z' | Out-Null
        $b = New-TestExport $root 'b' 'vbr-b' '2026-11-18T10:00:00Z'
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('x', '0', '3', '1'))
        Mock Read-Host { $script:answers.Dequeue() }
        Resolve-VBRImportPath -OutputRoot $root | Should -Be (Get-Item $b).FullName
        Should -Invoke Read-Host -Times 4 -Exactly
    }
}

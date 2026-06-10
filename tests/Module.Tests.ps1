# Module.Tests.ps1
# Smoke tests for the VbrMigrationAutomation module. Verifies the module
# loads cleanly and exports the expected public surface — catches accidental
# breakage from refactors, renames, or missing files in Public/.

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation'
    Import-Module $script:ModuleRoot -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module VbrMigrationAutomation -ErrorAction SilentlyContinue
}

Describe 'VbrMigrationAutomation module' {
    It 'imports without errors' {
        Get-Module VbrMigrationAutomation | Should -Not -BeNullOrEmpty
    }

    It 'declares the expected manifest version' {
        $manifest = Test-ModuleManifest -Path (Join-Path $script:ModuleRoot 'VbrMigrationAutomation.psd1')
        $manifest.Version | Should -BeOfType [version]
    }

    It 'targets PowerShell 7 or newer in the manifest' {
        $manifest = Test-ModuleManifest -Path (Join-Path $script:ModuleRoot 'VbrMigrationAutomation.psd1')
        $manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
    }

    It 'exports 26 functions (manifest in sync with Public/)' {
        $exported = Get-Command -Module VbrMigrationAutomation -CommandType Function
        $exported.Count | Should -Be 26
    }

    It 'does not leak Private/ helpers into the exported surface' {
        $private = @('Format-RedactedJson','Get-VBRPaginatedData','Invoke-AutomationSession','Invoke-VBRConfigBackup')
        foreach ($name in $private) {
            Get-Command $name -Module VbrMigrationAutomation -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty -Because "$name is a Private/ helper and must not be exported"
        }
    }
}

Describe 'Exported function surface' {
    Context 'authentication' {
        It 'exports <_>' -ForEach @('Connect-VBRApi') {
            Get-Command $_ -Module VbrMigrationAutomation -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'top-level wrappers' {
        It 'exports <_>' -ForEach @(
            'Invoke-VBRMigrationExport'
            'Invoke-VBRMigrationImport'
        ) {
            Get-Command $_ -Module VbrMigrationAutomation -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'orchestrators' {
        It 'exports <_>' -ForEach @(
            'Export-VBRMigration'
            'Import-VBRMigration'
            'Export-VBRAgentMigration'
            'Import-VBRAgentMigration'
        ) {
            Get-Command $_ -Module VbrMigrationAutomation -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'per-component exports' {
        It 'exports <_>' -ForEach @(
            'Export-VBRAgentJob'
            'Export-VBRAgentProtectionGroup'
            'Export-VBRCloudCredential'
            'Export-VBRCredential'
            'Export-VBREncryptionPassword'
            'Export-VBRJob'
            'Export-VBRManagedServer'
            'Export-VBRProxy'
            'Export-VBRRepository'
        ) {
            Get-Command $_ -Module VbrMigrationAutomation -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'per-component imports' {
        It 'exports <_>' -ForEach @(
            'Import-VBRAgentJob'
            'Import-VBRAgentProtectionGroup'
            'Import-VBRCloudCredential'
            'Import-VBRCredential'
            'Import-VBREncryptionPassword'
            'Import-VBRJob'
            'Import-VBRManagedServer'
            'Import-VBRProxy'
            'Import-VBRRepository'
            'Import-VBRSourceServerReference'
        ) {
            Get-Command $_ -Module VbrMigrationAutomation -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Public function syntax' {
    It 'parses every Public/*.ps1 file without errors' {
        $publicFiles = Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public') -Filter '*.ps1'
        $publicFiles.Count | Should -BeGreaterThan 0

        foreach ($file in $publicFiles) {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$errors
            ) | Out-Null
            $errors | Should -BeNullOrEmpty -Because "$($file.Name) should parse cleanly"
        }
    }

    It 'parses every Private/*.ps1 file without errors' {
        $privateFiles = Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Private') -Filter '*.ps1'
        $privateFiles.Count | Should -BeGreaterThan 0

        foreach ($file in $privateFiles) {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$errors
            ) | Out-Null
            $errors | Should -BeNullOrEmpty -Because "$($file.Name) should parse cleanly"
        }
    }
}

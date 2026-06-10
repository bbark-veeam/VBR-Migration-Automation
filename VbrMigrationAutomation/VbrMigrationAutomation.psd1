@{
    RootModule        = 'VbrMigrationAutomation.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b8d3c2a1-7e4f-4a9b-9c1d-5f2e7b8a3d4c'
    Author            = 'Brad Barker'
    Copyright         = '(c) 2026 Brad Barker. Licensed under the MIT License.'
    Description       = 'Automates export and import of Veeam Backup & Replication server configuration between servers via the Veeam VBR REST API. Migrates credentials, repositories, proxies, jobs, agent protection groups, and agent backup jobs.'

    PowerShellVersion = '7.0'

    # Functions exported by this module.
    FunctionsToExport = @(
        # Authentication
        'Connect-VBRApi'

        # Top-level wrappers (single command for a full export or import)
        'Invoke-VBRMigrationExport'
        'Invoke-VBRMigrationImport'

        # Orchestrators (run a scope of components in dependency order)
        'Export-VBRMigration'
        'Import-VBRMigration'
        'Export-VBRAgentMigration'
        'Import-VBRAgentMigration'

        # Per-component exports
        'Export-VBRAgentJob'
        'Export-VBRAgentProtectionGroup'
        'Export-VBRCloudCredential'
        'Export-VBRCredential'
        'Export-VBREncryptionPassword'
        'Export-VBRJob'
        'Export-VBRManagedServer'
        'Export-VBRProxy'
        'Export-VBRRepository'

        # Per-component imports
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
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Veeam', 'VBR', 'Backup', 'Migration', 'REST', 'API')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'Pre-release (0.x, in testing). See CHANGELOG.md for changes per version.'
        }
    }
}

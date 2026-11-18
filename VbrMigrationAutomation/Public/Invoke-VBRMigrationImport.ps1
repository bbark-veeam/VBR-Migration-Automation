# Invoke-VBRMigrationImport
# Single-command wrapper that runs Import-VBRMigration followed by
# Import-VBRAgentMigration against the same target server. Authenticates once,
# prompts for the configuration-backup decision once, and passes the resulting
# connection plus -SkipBackupPrompt through to both phases so the operator is
# prompted only one time.
#
# If the main import fails, the agent import is not attempted because agent
# objects depend on credentials and other resources created during the main
# migration.

function Invoke-VBRMigrationImport {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int]                           $Port           = 9419,
        [string]                        $InputPath,
        [string]                        $SourceVBR,
        [switch]                        $IsVSA,
        [switch]                        $SkipCloudRepos,
        [switch]                        $Quiet
    )

    $InputPath = Resolve-VBRImportPath -InputPath $InputPath

    $cred = Get-Credential -Message "Enter credentials for $Server"
    $conn = Connect-VBRApi -Server $Server -Port $Port -Credential $cred

    # Prompt for the configuration backup once at the wrapper level. Child
    # orchestrators receive -SkipBackupPrompt so they don't ask again.
    $answer = Read-Host "Create a Veeam configuration backup before importing? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
        Invoke-VBRConfigBackup -Connection $conn
    } else {
        Write-Warning "Skipping configuration backup. Proceed at your own risk."
    }

    Write-Host "`n========================================="
    Write-Host "Phase 1 of 2: Main migration (Import-VBRMigration)"
    Write-Host "=========================================`n"

    try {
        Import-VBRMigration -Server $Server -Port $Port -InputPath $InputPath `
            -SourceVBR $SourceVBR -IsVSA:$IsVSA -SkipCloudRepos:$SkipCloudRepos `
            -Connection $conn -SkipBackupPrompt -Quiet:$Quiet
    } catch {
        Write-Error "Main import failed: $_. Halting before agent import — agents depend on credentials and other objects from the main migration."
        throw
    }

    Write-Host "`n========================================="
    Write-Host "Phase 2 of 2: Agent migration (Import-VBRAgentMigration)"
    Write-Host "=========================================`n"

    try {
        Import-VBRAgentMigration -Server $Server -Port $Port -InputPath $InputPath `
            -Connection $conn -SkipBackupPrompt -Quiet:$Quiet
    } catch {
        Write-Error "Agent import failed: $_"
        throw
    }

    Write-Host "`n========================================="
    Write-Host "Full migration complete (main + agents)."
    Write-Host "========================================="
}

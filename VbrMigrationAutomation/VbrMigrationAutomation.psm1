#Requires -Version 7

# Root module — discovers and loads all function files from Public/ and Private/,
# then exports only the Public ones for consumers of the module.

$Public  = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1"  -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)

foreach ($file in $Public + $Private) {
    try {
        . $file.FullName
    } catch {
        Write-Error "VbrMigrationAutomation: failed to load $($file.Name) — $_"
    }
}

if ($Public.Count -gt 0) {
    Export-ModuleMember -Function $Public.BaseName
}

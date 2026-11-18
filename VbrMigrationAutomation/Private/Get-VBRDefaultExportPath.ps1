# Get-VBRDefaultExportPath
# Returns the default export directory for a source server:
# <current dir>\output\<server>_<yyyy-MM-dd_HHmmss>. The server name and
# timestamp keep exports from several sources and runs apart.

function Get-VBRDefaultExportPath {
    param(
        [Parameter(Mandatory)] [string] $Server,
        [datetime]                      $Timestamp = (Get-Date)
    )

    $safeServer = $Server -replace '[^\w.-]', '_'
    $folder     = '{0}_{1}' -f $safeServer, $Timestamp.ToString('yyyy-MM-dd_HHmmss')
    return Join-Path (Join-Path (Get-Location).Path 'output') $folder
}

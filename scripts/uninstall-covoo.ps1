$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'install-common.ps1')
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\covoo'
Uninstall-Covoo $installRoot (Join-Path ([Environment]::GetFolderPath('Programs')) 'covoo') `
    (Join-Path $env:LOCALAPPDATA 'covoo')
Write-Host 'Removed covoo program files and Start menu entries. Saved pairing and recordings are kept.'

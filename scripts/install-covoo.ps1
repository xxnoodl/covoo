$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'install-common.ps1')
$target = Install-Covoo $PSScriptRoot (Join-Path $env:LOCALAPPDATA 'Programs\covoo') `
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'covoo') (Join-Path $env:LOCALAPPDATA 'covoo')
Write-Host "Installed covoo for this account. Open covoo from the Start menu. Program files: $target"

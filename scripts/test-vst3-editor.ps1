param([string]$ReceiverPath = 'target/release/windows-receiver.exe',
    [string]$HostPath = 'build/vst3-prototype/bin/Release/covoo_editor_host.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repo ('build/vst3-editor-check-' + [guid]::NewGuid().ToString('N'))
$binary = Join-Path $root 'Contents/x86_64-win'
$runtime = Join-Path $root 'Contents/Resources/runtime'
[IO.Directory]::CreateDirectory($binary) | Out-Null
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Copy-Item -LiteralPath $HostPath -Destination (Join-Path $binary 'editor-host.exe')
Copy-Item -LiteralPath $ReceiverPath -Destination (Join-Path $runtime 'covoo-receiver.exe')
foreach ($name in @('desktop-common.ps1', 'plugin-session.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $runtime }
$savedAppData = $env:LOCALAPPDATA
$savedLinks = $env:COVOO_VST3_LINK_DIRECTORY
try {
    $env:LOCALAPPDATA = Join-Path $root 'user-data'
    $env:COVOO_VST3_LINK_DIRECTORY = Join-Path $root 'links'
    & (Join-Path $binary 'editor-host.exe')
    if ($LASTEXITCODE -ne 0) { throw "Editor/receiver lifecycle failed ($LASTEXITCODE). See $root" }
    foreach ($run in Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'covoo/vst3-runs') -Directory) {
        if (Test-Path -LiteralPath (Join-Path $run.FullName 'pairing.bmp')) { throw 'Stopped session retained QR.' }
    }
    Write-Host 'Isolated editor checks passed. No Live, physical audio or real user pairing touched.'
} finally {
    $env:LOCALAPPDATA = $savedAppData
    $env:COVOO_VST3_LINK_DIRECTORY = $savedLinks
}

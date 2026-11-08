param([string]$PluginPath = 'build/vst3-prototype/VST3/Release/covoo_source.vst3', [string]$Destination)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $repo ('build/vst3-test-' + [guid]::NewGuid().ToString('N')) }
$Destination = [IO.Path]::GetFullPath($Destination)
$bundle = (Resolve-Path -LiteralPath $PluginPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'Contents/x86_64-win/covoo_source.vst3'))) { throw 'Build the x64 Covoo source bundle first.' }
if (Test-Path -LiteralPath $Destination) { throw 'Use a new destination directory.' }
# Reuse the receiver package manifest. No host search directory is touched.
& (Join-Path $PSScriptRoot 'package-windows.ps1') -Destination (Join-Path $Destination 'receiver')
Copy-Item -LiteralPath $bundle -Destination (Join-Path $Destination 'covoo_source.vst3') -Recurse
$runtime = Join-Path $Destination 'covoo_source.vst3/Contents/Resources/runtime'
[IO.Directory]::CreateDirectory($runtime) | Out-Null
foreach ($name in @('covoo-receiver.exe', 'desktop-common.ps1')) {
    Copy-Item -LiteralPath (Join-Path $Destination "receiver/$name") -Destination (Join-Path $runtime $name)
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'plugin-session.ps1') -Destination (Join-Path $runtime 'plugin-session.ps1')
Copy-Item -LiteralPath (Join-Path $Destination 'receiver/licenses') -Destination (Join-Path $runtime 'licenses') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'docs/testing/vst3-quick-start.md') -Destination (Join-Path $Destination 'Read-me-first.md')
$files = @(Get-ChildItem -LiteralPath $Destination -File -Recurse | ForEach-Object {
    @{ path = $_.FullName.Substring($Destination.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$manifest = @{ product = 'covoo development VST3 test'; source_revision = (& git -C $repo rev-parse HEAD).Trim();
    source_dirty = [bool](& git -C $repo status --porcelain); physical_accepted = $false; files = $files }
[IO.File]::WriteAllText((Join-Path $Destination 'test-manifest.json'), ($manifest | ConvertTo-Json -Depth 5))
Compress-Archive -Path (Join-Path $Destination '*') -DestinationPath "$Destination.zip"
Write-Host "Uninstalled development bundle: $Destination.zip"

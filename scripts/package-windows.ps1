param([string]$ReceiverPath, [string]$Destination)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $ReceiverPath) { $ReceiverPath = Join-Path $repo 'target\release\windows-receiver.exe' }
if (-not $Destination) { $Destination = Join-Path $repo ('build\windows-' + [guid]::NewGuid().ToString('N')) }
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) { throw 'Package destination must be a new folder.' }
if (-not (Test-Path -LiteralPath $ReceiverPath)) { throw 'Build the release receiver first.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework C# compiler is unavailable.' }
[IO.Directory]::CreateDirectory($Destination) | Out-Null
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll `
    ("/out:" + (Join-Path $Destination 'covoo.exe')) (Join-Path $repo 'apps\windows\Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Desktop launcher build failed.' }
[IO.File]::Copy([IO.Path]::GetFullPath($ReceiverPath), (Join-Path $Destination 'covoo-receiver.exe'))
# Explicit input list: no recordings, local settings, credentials or build logs.
$scripts = @('desktop.ps1', 'desktop-common.ps1', 'receiver-profiles.ps1', 'daw-latency.ps1', 'start-desktop.cmd',
    'install-covoo.cmd', 'install-covoo.ps1', 'install-common.ps1', 'uninstall-covoo.cmd', 'uninstall-covoo.ps1',
    'start-receiver.cmd', 'start-daw.cmd', 'start-daw-fast.cmd', 'start-daw-lowlatency.cmd',
    'start-daw-balanced.cmd', 'start-headphone-check.cmd', 'headphone-check.ps1',
    'latency-audit.py', 'session-dashboard.py', 'compare-recordings.py', 'compare-segments.py', 'network-snapshot.ps1')
foreach ($name in $scripts) { [IO.File]::Copy((Join-Path $PSScriptRoot $name), (Join-Path $Destination $name)) }
$documents = @{
    'docs/testing/desktop-setup.md' = 'Desktop-setup.md'
    'docs/testing/ableton-monitoring.md' = 'Ableton-monitoring.md'
    'docs/testing/m3-device.md' = 'DAW-setup.md'
    'docs/performance/latency-investigation.md' = 'Latency-check.md'
    'docs/testing/low-period-output.md' = 'Low-period-test.md'
    'docs/testing/direct-headphones.md' = 'Headphone-check.md'
    'docs/testing/receiver-dashboard.md' = 'Receiver-status.md'
    'docs/testing/windows-desktop-install.md' = 'Read-me-first.md'
}
foreach ($source in $documents.Keys) {
    $document = [IO.File]::ReadAllText((Join-Path $repo $source)).Replace('(windows-desktop-install.md)', '(Read-me-first.md)')
    [IO.File]::WriteAllText((Join-Path $Destination $documents[$source]), $document)
}
$licenseFiles = @('audio_thread_priority-MPL-2.0.txt', 'OUTPUT-COMPONENTS.md', 'wasapi-MIT.txt')
[IO.Directory]::CreateDirectory((Join-Path $Destination 'licenses')) | Out-Null
foreach ($name in $licenseFiles) { [IO.File]::Copy((Join-Path $repo "licenses/$name"), (Join-Path $Destination "licenses/$name")) }
$files = @(Get-ChildItem -LiteralPath $Destination -File -Recurse | Sort-Object FullName | ForEach-Object {
    @{ path = $_.FullName.Substring($Destination.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$revision = (& git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not identify source revision.' }
$dirty = [bool](& git -C $repo status --porcelain)
$hash = [Security.Cryptography.SHA256]::Create()
try {
    $fileList = ($files | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"
    $digest = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($fileList))).Replace('-', '').ToLowerInvariant()
} finally { $hash.Dispose() }
$manifest = @{ schema = 1; product = 'covoo'; build_id = $revision.Substring(0, 7) + '-' + $digest.Substring(0, 12);
    source_revision = $revision; source_dirty = $dirty; files = $files }
[IO.File]::WriteAllText((Join-Path $Destination 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5))
Compress-Archive -Path (Join-Path $Destination '*') -DestinationPath "$Destination.zip" -Force
Write-Host "Windows package: $Destination.zip"

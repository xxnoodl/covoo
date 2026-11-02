param([string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'install-common.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $repo ('build\install-check-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($folder) | Out-Null
if (-not $PackageDirectory) {
    $PackageDirectory = Join-Path $folder 'package'
    & (Join-Path $PSScriptRoot 'package-windows.ps1') -Destination $PackageDirectory
}
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
$install = Join-Path $folder 'programs with spaces\covoo'
$shortcuts = Join-Path $folder 'start menu\covoo'
$data = Join-Path $folder 'data'
[IO.Directory]::CreateDirectory($data) | Out-Null
[IO.File]::WriteAllText((Join-Path $data 'pairing.dpapi'), 'unchanged test secret')
[IO.File]::WriteAllText((Join-Path $data 'take.wav'), 'unchanged test audio')

function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}

$manifest = Get-PackageManifest $PackageDirectory
Assert-True (-not (@($manifest.files.path) -match '(pairing|recordings|\.dpapi|\.wav|\.p12|\.ipa)$')) 'Package contains private/runtime files.'
$expanded = Join-Path $folder 'expanded'
Expand-Archive -LiteralPath "$PackageDirectory.zip" -DestinationPath $expanded
Get-PackageManifest $expanded | Out-Null
Assert-True (@(Get-ChildItem -LiteralPath $expanded -Recurse -File).Count -eq @($manifest.files).Count + 1) 'ZIP has extra or missing files.'
$target = Install-Covoo $expanded $install $shortcuts $data
Assert-True ([IO.File]::Exists((Join-Path $target 'covoo.exe'))) 'Launcher not installed.'
$shell = New-Object -ComObject WScript.Shell
Assert-True ($shell.CreateShortcut((Join-Path $shortcuts 'covoo.lnk')).TargetPath -eq (Join-Path $target 'covoo.exe')) 'Start menu target is wrong.'
$again = Install-Covoo $expanded $install $shortcuts $data
Assert-True ($again -eq $target) 'Same-build reinstall is not idempotent.'

# Launch the actual packaged window, use loopback only, then close gracefully.
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = Join-Path $target 'covoo.exe'
$info.Arguments = '--smoke-test'
$info.UseShellExecute = $false; $info.CreateNoWindow = $true
$info.RedirectStandardError = $true; $info.RedirectStandardOutput = $true
$process = [Diagnostics.Process]::Start($info)
try {
    $errors = $process.StandardError.ReadToEndAsync()
    $output = $process.StandardOutput.ReadToEndAsync()
    Assert-True ($process.WaitForExit(30000)) 'Packaged desktop did not finish its UI check.'
    Assert-True ($process.ExitCode -eq 0) ('Packaged desktop failed: ' + $errors.GetAwaiter().GetResult())
} finally { $process.Dispose() }

# A held desktop lock must refuse both setup and uninstall without touching files.
$busy = [IO.File]::Open((Join-Path $data 'desktop.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    Assert-Rejected { Install-Covoo $expanded $install $shortcuts $data } 'Update ignored an open desktop.'
    Assert-Rejected { Uninstall-Covoo $install $shortcuts $data } 'Uninstall ignored an open desktop.'
} finally { $busy.Dispose() }

# Failed update must leave the previous build and shortcut intact.
$readme = Join-Path $expanded 'Read-me-first.md'
$original = [IO.File]::ReadAllBytes($readme)
[IO.File]::AppendAllText($readme, 'tampered')
Assert-Rejected { Install-Covoo $expanded $install $shortcuts $data } 'Damaged package installed.'
Assert-True ($shell.CreateShortcut((Join-Path $shortcuts 'covoo.lnk')).TargetPath -eq (Join-Path $target 'covoo.exe')) 'Failed update changed shortcut.'
[IO.File]::WriteAllBytes($readme, $original)

# Traversal in a manifest fails before copying outside the installation root.
$manifestPath = Join-Path $expanded 'manifest.json'
$originalManifest = [IO.File]::ReadAllText($manifestPath)
$badManifest = $originalManifest | ConvertFrom-Json
$badManifest.files[0].path = '../escape.txt'
[IO.File]::WriteAllText($manifestPath, ($badManifest | ConvertTo-Json -Depth 5))
Assert-Rejected { Install-Covoo $expanded $install $shortcuts $data } 'Traversal was accepted.'
[IO.File]::WriteAllText($manifestPath, $originalManifest)

# A distinct valid build activates without replacing the old one.
[IO.File]::AppendAllText($readme, "`r`nTest update.")
$updated = $originalManifest | ConvertFrom-Json
($updated.files | Where-Object path -eq 'Read-me-first.md').sha256 = (Get-FileHash -LiteralPath $readme).Hash.ToLowerInvariant()
$updated.build_id = $updated.build_id.Substring(0, 8) + '123456789abc'
[IO.File]::WriteAllText($manifestPath, ($updated | ConvertTo-Json -Depth 5))
$newTarget = Install-Covoo $expanded $install $shortcuts $data
Assert-True ($newTarget -ne $target -and [IO.File]::Exists((Join-Path $target 'covoo.exe'))) 'Update replaced the previous build.'
Assert-True ($shell.CreateShortcut((Join-Path $shortcuts 'covoo.lnk')).TargetPath -eq (Join-Path $newTarget 'covoo.exe')) 'Update did not activate.'

# Unknown files and user data survive uninstall; only declared program files go.
$keep = Join-Path $target 'user-note.txt'
[IO.File]::WriteAllText($keep, 'keep this')
Uninstall-Covoo $install $shortcuts $data
Assert-True (-not [IO.File]::Exists((Join-Path $target 'covoo.exe'))) 'Old program files remain.'
Assert-True (-not [IO.File]::Exists((Join-Path $newTarget 'covoo.exe'))) 'Updated program files remain.'
Assert-True (-not [IO.File]::Exists((Join-Path $shortcuts 'covoo.lnk'))) 'Shortcut remains.'
Assert-True ([IO.File]::ReadAllText($keep) -eq 'keep this') 'Uninstall removed an unknown file.'
Assert-True ([IO.File]::ReadAllText((Join-Path $data 'pairing.dpapi')) -eq 'unchanged test secret') 'Setup changed saved pairing.'
Assert-True ([IO.File]::ReadAllText((Join-Path $data 'take.wav')) -eq 'unchanged test audio') 'Setup changed recordings.'
Write-Host 'Package ZIP, hashes, installed launcher, shortcuts, reinstall/update, damaged update, traversal, busy desktop and data-preserving uninstall passed.'

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -products '*' -latest -property installationPath
if (-not $installation) { throw 'Visual Studio C++ Build Tools not found.' }
$tools = Get-ChildItem (Join-Path $installation 'VC\Tools\MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\Hostx64\x64\cl.exe')) } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
$sdk = Get-ChildItem (Join-Path $kits 'Include') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'ucrt\assert.h')) -and
        (Test-Path -LiteralPath (Join-Path $kits "Lib\$($_.Name)\ucrt\x64\ucrt.lib")) } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $tools -or -not $sdk) { throw 'C++ tools or Windows SDK not found.' }
Write-Host "C tools $($tools.Name), SDK $($sdk.Name)"
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$compiler = Join-Path $tools.FullName 'bin\Hostx64\x64\cl.exe'
$options = @('/nologo', '/std:c11', '/experimental:c11atomics', '/W4', '/WX',
    '/I', (Join-Path $tools.FullName 'include'),
    '/I', (Join-Path $sdk.FullName 'ucrt'),
    '/I', (Join-Path $sdk.FullName 'shared'),
    '/I', (Join-Path $repo 'apps\ios\Native'),
    (Join-Path $repo 'apps\ios\Native\PCMQueue.c'),
    (Join-Path $repo 'tests\native\pcm_queue_test.c'),
    "/Fo$build\", "/Fe$build\pcm-queue-test.exe", '/link',
    "/LIBPATH:$($tools.FullName)\lib\x64",
    "/LIBPATH:$kits\Lib\$($sdk.Name)\ucrt\x64",
    "/LIBPATH:$kits\Lib\$($sdk.Name)\um\x64")
& $compiler @options
if ($LASTEXITCODE -ne 0) { throw 'Native queue compilation failed.' }
& (Join-Path $build 'pcm-queue-test.exe')
if ($LASTEXITCODE -ne 0) { throw 'Native queue tests failed.' }
Write-Host 'Windows queue subset passed. POSIX concurrency and sanitizers run on Linux/macOS.'

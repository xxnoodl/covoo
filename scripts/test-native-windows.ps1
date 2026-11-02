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
    '/I', (Join-Path $repo 'apps\ios\Native'), "/Fo$build\")
$libraries = @('/link',
    "/LIBPATH:$($tools.FullName)\lib\x64",
    "/LIBPATH:$kits\Lib\$($sdk.Name)\ucrt\x64",
    "/LIBPATH:$kits\Lib\$($sdk.Name)\um\x64")
foreach ($test in @(@('PCMQueue.c', 'pcm_queue_test.c', 'pcm-queue-test.exe'),
                   @('MonitorGate.c', 'monitor_gate_test.c', 'monitor-gate-test.exe'))) {
    $sources = @((Join-Path $repo "apps\ios\Native\$($test[0])"),
                 (Join-Path $repo "tests\native\$($test[1])"))
    $executable = Join-Path $build $test[2]
    & $compiler @options @sources "/Fe$executable" @libraries
    if ($LASTEXITCODE -ne 0) { throw "Native compilation failed: $($test[0])" }
    & $executable
    if ($LASTEXITCODE -ne 0) { throw "Native test failed: $($test[1])" }
}
Write-Host 'Windows queue subset passed. POSIX concurrency and sanitizers run on Linux/macOS.'

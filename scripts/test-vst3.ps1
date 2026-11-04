param([string]$SdkRoot, [string]$BuildDirectory, [string]$Generator)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$cmake = Get-Command cmake.exe -ErrorAction SilentlyContinue
if ($cmake) { $cmakePath = $cmake.Source }
else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'CMake 3.25+ and Visual Studio C++ tools are required.' }
    $instance = & $vswhere -products '*' -latest -format json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $instance) { throw 'Visual Studio inventory failed.' }
    $cmakePath = Join-Path $instance.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $cmakePath)) { throw 'CMake not found.' }
}
if (-not $BuildDirectory) { $BuildDirectory = if ($SdkRoot) { 'build/vst3-prototype' } else { 'build/vst3-core' } }
$build = [IO.Path]::GetFullPath((Join-Path $repo $BuildDirectory))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
if (-not $build.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Use a build subdirectory inside the repository build folder.'
}

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Program" }
}

$configure = @('-S', (Join-Path $repo 'apps/vst3'), '-B', $build, '-A', 'x64')
if ($Generator) { $configure += @('-G', $Generator) }
if ($SdkRoot) {
    $SdkRoot = (Resolve-Path -LiteralPath $SdkRoot).Path
    $pins = [ordered]@{
        '.' = '3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96'
        'base' = 'fcf9da0bd27a16f7f03773a3a39822f28f5c8477'
        'cmake' = '054c9143cbb8d47fc4694e473f2ee3b4d951a8f5'
        'pluginterfaces' = '4f547e8e102b47de4a8b8aaf343c73b700786372'
        'public.sdk' = '586dc5e6c8012c3e4b01c79389375cbe96bdb1da'
    }
    foreach ($entry in $pins.GetEnumerator()) {
        $checkout = Join-Path $SdkRoot $entry.Key
        $commit = & git -C $checkout rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $commit -ne $entry.Value) { throw "SDK pin mismatch: $($entry.Key)" }
        Invoke-Checked 'git' @('-C', $checkout, 'diff', '--quiet', 'HEAD', '--')
    }
    $configure += "-DCOVOO_VST3_SDK=$($SdkRoot.Replace('\', '/'))"
} else { $configure += '-DCOVOO_VST3_SDK=' }
Invoke-Checked $cmakePath $configure
$targets = @('covoo_source_test')
if ($SdkRoot) { $targets += @('covoo_source', 'covoo_processor_test', 'covoo_bridge_host') }
$previousDirectory = $env:COVOO_VST3_LINK_DIRECTORY
$env:COVOO_VST3_LINK_DIRECTORY = Join-Path $build 'validator-links'
try {
Invoke-Checked $cmakePath (@('--build', $build, '--config', 'Release', '--parallel', '4', '--target') + $targets)
$ctest = Join-Path (Split-Path -Parent $cmakePath) 'ctest.exe'
Invoke-Checked $ctest @('--test-dir', $build, '-C', 'Release', '--output-on-failure')
} finally { $env:COVOO_VST3_LINK_DIRECTORY = $previousDirectory }
Write-Host 'VST source checks passed. No Live, physical endpoint or latency measurement. Run test-vst3-bridge.ps1 separately for receiver interoperability.'

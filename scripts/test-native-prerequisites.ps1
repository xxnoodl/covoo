$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-prerequisites.ps1')
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
$root = Join-Path (Split-Path -Parent $PSScriptRoot) ('build\native-inventory-check-' + [guid]::NewGuid().ToString('N'))
$kits = Join-Path $root 'kits'
$vs17 = Join-Path $root 'vs17'
$vs18 = Join-Path $root 'vs18'
function New-FixtureFile([string]$Path) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, 'fixture only; never executed')
}
foreach ($vs in @($vs17, $vs18)) {
    New-FixtureFile (Join-Path $vs 'VC\Tools\MSVC\14.44.00000\bin\Hostx64\x64\cl.exe')
    New-FixtureFile (Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe')
}
$instance17 = [pscustomobject]@{ displayName = 'VS 2022 fixture'; installationVersion = '17.14.0'; installationPath = $vs17 }
$instance18 = [pscustomobject]@{ displayName = 'VS 2026 fixture'; installationVersion = '18.6.0'; installationPath = $vs18 }
$empty = Get-NativeBuildInventory $kits @()
Assert-True (-not $empty.kernel_layout_candidate -and -not $empty.native_driver_build_verified) 'Missing SDK became a verified driver environment.'
$version = '10.0.26100.0'
foreach ($path in @("Include\$version\um\Windows.h", "Include\$version\ucrt\stdio.h",
        "Lib\$version\um\x64\kernel32.lib", "Lib\$version\ucrt\x64\ucrt.lib")) {
    New-FixtureFile (Join-Path $kits $path)
}
$userOnly = Get-NativeBuildInventory $kits @($instance18)
Assert-True ($userOnly.user_mode_layout_candidate -and -not $userOnly.kernel_layout_candidate) 'User-mode SDK was mistaken for WDK.'
foreach ($path in @("Include\$version\km\ntddk.h", "Include\$version\km\portcls.h",
        "Lib\$version\km\x64\ntoskrnl.lib", "Lib\$version\km\x64\portcls.lib",
        "build\$version\WindowsDriver.Common.targets")) { New-FixtureFile (Join-Path $kits $path) }
$wrongVs = Get-NativeBuildInventory $kits @($instance18)
Assert-True (-not $wrongVs.kernel_layout_candidate) 'Unsupported VS/kit family became a kernel candidate.'
$matched = Get-NativeBuildInventory $kits @($instance17, $instance18)
Assert-True ($matched.kernel_layout_candidate -and -not $matched.native_driver_build_verified) 'Matching files claim an actual driver build.'
Assert-True ($matched.kits[0].matching_visual_studio[0] -eq 'VS 2022 fixture') 'Latest VS hid the matching older installation.'
$unknown = Join-Path $kits 'Include\10.0.99999.0'
[IO.Directory]::CreateDirectory($unknown) | Out-Null
$unsupported = Get-NativeBuildInventory $kits @($instance18)
Assert-True (-not $unsupported.kits[0].kernel_layout_candidate -and $null -eq $unsupported.kits[0].documented_vs_major) 'Unknown SDK family was guessed compatible.'
$newKits = Join-Path $root 'kits28000'
Get-ChildItem -LiteralPath $kits -File -Recurse | Where-Object { $_.FullName -match '26100' } | ForEach-Object {
    $relative = $_.FullName.Substring($kits.Length + 1).Replace('26100', '28000')
    New-FixtureFile (Join-Path $newKits $relative)
}
$newMatched = Get-NativeBuildInventory $newKits @($instance18)
Assert-True ($newMatched.kernel_layout_candidate -and -not $newMatched.native_driver_build_verified) 'VS 2026/28000 layout was not identified without claiming a build.'
$noCompiler = [pscustomobject]@{ displayName = 'VS without compiler'; installationVersion = '18.6.0'; installationPath = (Join-Path $root 'empty-vs') }
$noCompilerResult = Get-NativeBuildInventory $newKits @($noCompiler)
Assert-True (-not $noCompilerResult.kernel_layout_candidate -and -not $noCompilerResult.user_mode_layout_candidate) 'Kits without compiler/MSBuild became build candidates.'
Write-Host 'Native inventory fixture checks passed: absent WDK, user SDK, mismatched VS, matching 26100/28000 layouts, missing compiler and unknown family. No driver/compiler executed.'

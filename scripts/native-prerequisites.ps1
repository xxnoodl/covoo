param([string]$KitsRoot, [string]$OutputPath, [switch]$RequireKernelLayout)

function Get-NativeBuildInventory([string]$Root, [object[]]$Instances) {
    $visualStudio = @()
    foreach ($instance in $Instances) {
        $tools = @(Get-ChildItem -LiteralPath (Join-Path $instance.installationPath 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\Hostx64\x64\cl.exe')) } |
            Sort-Object { [version]$_.Name } -Descending)
        $visualStudio += [pscustomobject]@{
            name = $instance.displayName
            version = $instance.installationVersion
            major = ([version]$instance.installationVersion).Major
            path = $instance.installationPath
            msbuild_present = Test-Path -LiteralPath (Join-Path $instance.installationPath 'MSBuild\Current\Bin\MSBuild.exe')
            compiler_versions = @($tools | ForEach-Object { $_.Name })
            cmake_present = Test-Path -LiteralPath (Join-Path $instance.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
        }
    }
    $kits = @()
    $versions = @(Get-ChildItem -LiteralPath (Join-Path $Root 'Include') -Directory -ErrorAction SilentlyContinue |
        Where-Object Name -Match '^\d+\.\d+\.\d+\.\d+$' | Sort-Object { [version]$_.Name } -Descending)
    foreach ($version in $versions) {
        $base = $version.Name
        $build = ([version]$base).Build
        # Current Microsoft matrix checked 2026-11-04. Unknown families require review.
        $vsMajor = switch ($build) { 28000 { 18 }; 26100 { 17 }; default { $null } }
        $checks = [ordered]@{}
        foreach ($entry in @(
            @('user_header', "Include\$base\um\Windows.h"),
            @('ucrt_header', "Include\$base\ucrt\stdio.h"),
            @('user_library_x64', "Lib\$base\um\x64\kernel32.lib"),
            @('ucrt_library_x64', "Lib\$base\ucrt\x64\ucrt.lib"),
            @('kernel_header', "Include\$base\km\ntddk.h"),
            @('portcls_header', "Include\$base\km\portcls.h"),
            @('kernel_library_x64', "Lib\$base\km\x64\ntoskrnl.lib"),
            @('portcls_library_x64', "Lib\$base\km\x64\portcls.lib"),
            @('driver_targets', "build\$base\WindowsDriver.Common.targets")
        )) { $checks[$entry[0]] = [IO.File]::Exists((Join-Path $Root $entry[1])) }
        $missing = @($checks.Keys | Where-Object { -not $checks[$_] })
        $matching = @($visualStudio | Where-Object { $_.major -eq $vsMajor -and $_.msbuild_present -and $_.compiler_versions.Count -gt 0 })
        $userMode = @('user_header', 'ucrt_header', 'user_library_x64', 'ucrt_library_x64')
        $userReady = @($userMode | Where-Object { -not $checks[$_] }).Count -eq 0 -and
            @($visualStudio | Where-Object { $_.msbuild_present -and $_.compiler_versions.Count -gt 0 }).Count -gt 0
        $kits += [pscustomobject]@{
            folder_version = $base
            checks = [pscustomobject]$checks
            missing_files = $missing
            documented_vs_major = $vsMajor
            matching_visual_studio = @($matching | ForEach-Object { $_.name })
            user_mode_layout_candidate = $userReady
            kernel_layout_candidate = $missing.Count -eq 0 -and $null -ne $vsMajor -and $matching.Count -gt 0
            note = 'Folder/build-family checks only. Exact WDK patch, VS integration/toolset and project compilation remain unverified.'
        }
    }
    return [pscustomobject]@{
        observed_at_utc = [DateTime]::UtcNow.ToString('o')
        scope = 'Read-only x64 inventory of the supplied/default Windows Kits root and registered Visual Studio installations.'
        kits_root = $Root
        visual_studio = $visualStudio
        kits = $kits
        kernel_layout_candidate = @($kits | Where-Object kernel_layout_candidate).Count -gt 0
        user_mode_layout_candidate = @($kits | Where-Object user_mode_layout_candidate).Count -gt 0
        native_driver_build_verified = $false
        note = 'No compiler, project, driver, installer or signing tool was executed. This inventory does not establish a working WDK build or search all custom/NuGet/EWDK locations.'
        matrix_reference = 'https://learn.microsoft.com/en-us/windows-hardware/drivers/other-wdk-downloads'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    if (-not $KitsRoot) {
        $registered = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue
        $KitsRoot = if ($registered.KitsRoot10) { $registered.KitsRoot10 } else { Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10' }
    }
    $instances = @()
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $result = & $vswhere -all -products '*' -format json
        if ($LASTEXITCODE -ne 0) { throw 'Visual Studio inventory failed.' }
        $instances = @($result | ConvertFrom-Json)
    }
    $inventory = Get-NativeBuildInventory $KitsRoot $instances
    $json = $inventory | ConvertTo-Json -Depth 8
    if ($OutputPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json) }
    $bytes = [Text.Encoding]::UTF8.GetBytes($json + [Environment]::NewLine)
    [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
    if ($RequireKernelLayout -and -not $inventory.kernel_layout_candidate) { exit 2 }
}

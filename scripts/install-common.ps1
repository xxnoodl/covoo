# Per-user program files only. Pairing and recordings are never installation files.
$ErrorActionPreference = 'Stop'

function Assert-ChildPath([string]$Root, [string]$Path) {
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Installation path escapes its root.'
    }
    # Refuse junctions/symlinks, including any existing parent of the target.
    $current = $fullPath
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Installation paths cannot contain junctions or symbolic links.'
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $fullPath
}

function Get-PackageManifest([string]$Directory) {
    $manifestPath = Join-Path $Directory 'manifest.json'
    Assert-ChildPath $Directory $manifestPath | Out-Null
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.product -ne 'covoo' -or
        $manifest.build_id -notmatch '^[0-9a-f]{7,40}-[0-9a-f]{12}$' -or @($manifest.files).Count -lt 5) {
        throw 'Invalid covoo package manifest.'
    }
    $seen = @{}
    foreach ($file in $manifest.files) {
        if ($file.path -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or
            ($file.path -split '/') -contains '..' -or ($file.path -split '/') -contains '.' -or
            $file.path -match '\.(/|$)' -or $file.path -eq 'manifest.json' -or
            $file.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $seen.ContainsKey($file.path)) {
            throw 'Invalid package file entry.'
        }
        $seen[$file.path] = $true
        $path = Assert-ChildPath $Directory (Join-Path $Directory $file.path)
        if (-not [IO.File]::Exists($path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
            throw ('Package file failed verification: ' + $file.path)
        }
    }
    foreach ($required in @('covoo.exe', 'covoo-receiver.exe', 'desktop.ps1', 'desktop-common.ps1',
            'uninstall-covoo.cmd', 'uninstall-covoo.ps1', 'install-common.ps1')) {
        if (-not $seen.ContainsKey($required)) { throw ('Missing package file: ' + $required) }
    }
    return $manifest
}

function Open-SetupLock([string]$DataDirectory) {
    [IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
    try { return [IO.File]::Open((Join-Path $DataDirectory 'desktop.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Close the covoo desktop before installing or uninstalling.' }
}

function Write-InstallState([string]$Path, $State) {
    [IO.File]::WriteAllText("$Path.pending", ($State | ConvertTo-Json))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace("$Path.pending", $Path, [NullString]::Value) }
    else { [IO.File]::Move("$Path.pending", $Path) }
}

function Install-Covoo([string]$PackageDirectory, [string]$InstallRoot,
        [string]$ShortcutDirectory, [string]$DataDirectory) {
    $PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
    $manifest = Get-PackageManifest $PackageDirectory
    $statePath = Assert-ChildPath $InstallRoot (Join-Path $InstallRoot 'installation.json')
    $appRoot = Assert-ChildPath $InstallRoot (Join-Path $InstallRoot 'app')
    $target = Assert-ChildPath $InstallRoot (Join-Path $appRoot $manifest.build_id)
    if ((Test-Path -LiteralPath $InstallRoot) -and -not (Test-Path -LiteralPath $statePath) -and
        @(Get-ChildItem -LiteralPath $InstallRoot -Force).Count -gt 0) {
        throw 'The install folder contains files not owned by covoo.'
    }
    if (Test-Path -LiteralPath $statePath) {
        $oldState = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        if ($oldState.product -ne 'covoo' -or $oldState.schema -ne 1) { throw 'Invalid installation marker.' }
    }
    $shortcut = Assert-ChildPath $ShortcutDirectory (Join-Path $ShortcutDirectory 'covoo.lnk')
    $uninstallShortcut = Assert-ChildPath $ShortcutDirectory (Join-Path $ShortcutDirectory 'Uninstall covoo.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $backups = @{}
    foreach ($link in @($shortcut, $uninstallShortcut)) {
        if ([IO.File]::Exists($link)) {
            Assert-ChildPath $InstallRoot ($shell.CreateShortcut($link).TargetPath) | Out-Null
            $backups[$link] = [IO.File]::ReadAllBytes($link)
        }
    }
    $setupLock = Open-SetupLock $DataDirectory
    $stage = Join-Path $appRoot ('.pending-' + [guid]::NewGuid().ToString('N'))
    Assert-ChildPath $InstallRoot $stage | Out-Null
    $createdTarget = $false
    $activated = $false
    try {
        if (Test-Path -LiteralPath $target) {
            $existing = Get-PackageManifest $target
            if (([IO.File]::ReadAllText((Join-Path $target 'manifest.json'))) -ne
                ([IO.File]::ReadAllText((Join-Path $PackageDirectory 'manifest.json')))) {
                throw 'This build ID is already installed with different contents.'
            }
        } else {
            [IO.Directory]::CreateDirectory($stage) | Out-Null
            foreach ($file in $manifest.files) {
                $destination = Assert-ChildPath $InstallRoot (Join-Path $stage $file.path)
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
                [IO.File]::Copy((Join-Path $PackageDirectory $file.path), $destination)
            }
            [IO.File]::Copy((Join-Path $PackageDirectory 'manifest.json'), (Join-Path $stage 'manifest.json'))
            Get-PackageManifest $stage | Out-Null
            [IO.Directory]::Move($stage, $target)
            $createdTarget = $true
        }
        [IO.Directory]::CreateDirectory($ShortcutDirectory) | Out-Null
        foreach ($entry in @(@($shortcut, 'covoo.exe'), @($uninstallShortcut, 'uninstall-covoo.cmd'))) {
            $link = $shell.CreateShortcut($entry[0])
            $link.TargetPath = Join-Path $target $entry[1]
            $link.WorkingDirectory = $target
            $link.Description = 'covoo'
            $link.Save()
        }
        Write-InstallState $statePath @{ schema = 1; product = 'covoo'; active_build = $manifest.build_id }
        $activated = $true
        return $target
    } finally {
        if (-not $activated) {
            foreach ($link in @($shortcut, $uninstallShortcut)) {
                if ($backups.ContainsKey($link)) { [IO.File]::WriteAllBytes($link, $backups[$link]) }
                elseif ([IO.File]::Exists($link)) { Remove-Item -LiteralPath $link }
            }
            if ($createdTarget) {
                Assert-ChildPath $InstallRoot $target | Out-Null
                Remove-Item -LiteralPath $target -Recurse
            }
        }
        if (Test-Path -LiteralPath $stage) {
            Assert-ChildPath $InstallRoot $stage | Out-Null
            Remove-Item -LiteralPath $stage -Recurse
        }
        if (Test-Path -LiteralPath "$statePath.pending") { Remove-Item -LiteralPath "$statePath.pending" }
        $setupLock.Dispose()
    }
}

function Uninstall-Covoo([string]$InstallRoot, [string]$ShortcutDirectory, [string]$DataDirectory) {
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
    $statePath = Assert-ChildPath $InstallRoot (Join-Path $InstallRoot 'installation.json')
    $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    if ($state.product -ne 'covoo' -or $state.schema -ne 1) { throw 'Invalid installation marker.' }
    $appRoot = Assert-ChildPath $InstallRoot (Join-Path $InstallRoot 'app')
    # Validate every path before removing anything; do not adopt unknown folders.
    $versions = @(Get-ChildItem -LiteralPath $appRoot -Directory)
    foreach ($version in $versions) {
        Assert-ChildPath $InstallRoot $version.FullName | Out-Null
        Get-PackageManifest $version.FullName | Out-Null
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcuts = @('covoo.lnk', 'Uninstall covoo.lnk') | ForEach-Object {
        $path = Assert-ChildPath $ShortcutDirectory (Join-Path $ShortcutDirectory $_)
        if ([IO.File]::Exists($path)) {
            Assert-ChildPath $InstallRoot ($shell.CreateShortcut($path).TargetPath) | Out-Null
            $path
        }
    }
    $setupLock = Open-SetupLock $DataDirectory
    try {
        foreach ($shortcut in $shortcuts) { Remove-Item -LiteralPath $shortcut }
        foreach ($version in $versions) {
            $manifest = Get-PackageManifest $version.FullName
            $directories = @{}
            # Remove only declared program files; preserve unknown user files.
            foreach ($file in $manifest.files) {
                $path = Assert-ChildPath $InstallRoot (Join-Path $version.FullName $file.path)
                Remove-Item -LiteralPath $path
                $parent = [IO.Path]::GetDirectoryName($path)
                while ($parent -ne $version.FullName) {
                    $directories[$parent] = $true
                    $parent = [IO.Path]::GetDirectoryName($parent)
                }
            }
            Remove-Item -LiteralPath (Join-Path $version.FullName 'manifest.json')
            $directories.Keys | Sort-Object { $_.Length } -Descending | ForEach-Object {
                    Assert-ChildPath $InstallRoot $_ | Out-Null
                    if (@(Get-ChildItem -LiteralPath $_ -Force).Count -eq 0) { [IO.Directory]::Delete($_) }
                }
            if (@(Get-ChildItem -LiteralPath $version.FullName -Force).Count -eq 0) { [IO.Directory]::Delete($version.FullName) }
        }
        Remove-Item -LiteralPath $statePath
        foreach ($directory in @($appRoot, $InstallRoot, $ShortcutDirectory)) {
            if ((Test-Path -LiteralPath $directory) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
                [IO.Directory]::Delete($directory)
            }
        }
    } finally { $setupLock.Dispose() }
}

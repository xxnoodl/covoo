param([Parameter(Mandatory=$true)][string]$Instance, [Parameter(Mandatory=$true)][string]$Address,
    [Parameter(Mandatory=$true)][string]$Profile, [Parameter(Mandatory=$true)][string]$RunDirectory,
    [switch]$TestSession)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'desktop-common.ps1')
if ($Instance -cnotmatch '^[0-9a-f]{32}$' -or $Profile -cnotmatch '^[0-9a-f]{32}$') { throw 'Invalid plug-in identity.' }
$ip = $null
if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork' -or $Address -eq '0.0.0.0') { throw 'Choose an IPv4 interface.' }
$root = Join-Path $env:LOCALAPPDATA 'covoo/vst3-receivers'
$root = Join-Path $root $Profile
[IO.Directory]::CreateDirectory($root) | Out-Null
$RunDirectory = [IO.Path]::GetFullPath($RunDirectory)
$expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "covoo/vst3-runs/$Instance"))
if ($RunDirectory -ne $expected) { throw 'Unexpected plug-in session directory.' }
[IO.Directory]::CreateDirectory($RunDirectory) | Out-Null
$secretPath = Join-Path $root 'pairing.dpapi'
$configPath = Join-Path $root 'connection.json'
$process = $null; $lock = $null
function Publish-Text([string]$Text) {
    $pending = Join-Path $RunDirectory 'view.pending'
    [IO.File]::WriteAllText($pending, $Text)
    Move-Item -LiteralPath $pending -Destination (Join-Path $RunDirectory 'view.txt') -Force
}
try {
    $lock = [IO.File]::Open((Join-Path $root 'receiver.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $record = Read-Pairing $secretPath # Corrupt/locked DPAPI fails closed.
    $port = 0
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $port = [int]$config.port
        if ($port -lt 1 -or $port -gt 65535) { throw 'Invalid saved receiver port.' }
    }
    $recordings = Join-Path $env:LOCALAPPDATA ('covoo/recordings/vst3-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($recordings) | Out-Null
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'recordings.txt'), $recordings)
    $receiver = Join-Path $PSScriptRoot 'covoo-receiver.exe'
    $arguments = @('--serve', '--desktop-session', '--host', $Address, '--port', [string]$port,
        '--plugin-instance', $Instance, '--output', $recordings, '--seconds', '86400')
    if ($TestSession) { $arguments += '--no-discovery' }
    $process = New-ReceiverProcess $receiver $arguments
    $process.ControlInput.WriteLine($record); $process.ControlInput.Flush()
    $bootstrap = $process.StandardOutput.ReadLineAsync()
    if (-not $bootstrap.Wait(5000) -or -not $bootstrap.Result.StartsWith('COVOO_PAIRING ')) { throw 'Receiver bootstrap failed.' }
    Protect-Pairing $bootstrap.Result.Substring(14) $secretPath
    $channel = New-Object CovooReceiverChannel($process)
    $process.ControlInput.WriteLine('START'); $process.ControlInput.Flush()
    $configured = $false
    Publish-Text 'Starting receiver. Waiting for pairing QR…'
    while (-not $process.HasExited -and -not (Test-Path -LiteralPath (Join-Path $RunDirectory 'stop'))) {
        $line = $null
        while ($channel.TryRead([ref]$line)) {
            # Bootstrap was consumed privately above. Other diagnostics never enter project state.
            if ($line.StartsWith('covoo:')) { Publish-Text $line }
        }
        $statusPath = Join-Path $recordings 'status.json'
        if (Test-Path -LiteralPath $statusPath) {
            $status = [IO.File]::ReadAllText($statusPath) | ConvertFrom-Json
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [double]$status.updated_ms
            $state = if ($age -gt 5000) { 'Receiver status is stale.' } else { [string]$status.state }
            $fields = @($status.rows | Where-Object { $_[0] -in @('Last packet peak','Source format') } |
                ForEach-Object { $(if ($_[0] -eq 'Last packet peak') { 'Input level' } else { 'Format' }) + ': ' + $_[1] })
            foreach ($row in $status.rows) {
                if ($row[0] -eq 'VST3 live state') {
                    if ($row[1] -like '*host processing*') { $fields += 'Ableton is processing live audio.' }
                    elseif ($row[1] -like '*paused/offline*') { $fields += 'Ableton audio processing is paused.' }
                    elseif ($row[1] -match '(failed|stale)') { $fields += [string]$row[1] }
                }
                if ($row[0] -eq 'VST3 start error' -and $row[1] -ne 'None reported') { $fields += 'Audio connection error: ' + $row[1] }
            }
            Publish-Text ($state + "`r`n" + ($fields -join "`r`n"))
            if (-not $configured) {
                $addressRow = @($status.rows | Where-Object { $_[0] -eq 'Receiver address' })
                if ($addressRow.Count -eq 1) {
                    $actualPort = [int](([string]$addressRow[0][1]).Split(':')[-1])
                    [IO.File]::WriteAllText("$configPath.pending", (@{ port = $actualPort } | ConvertTo-Json))
                    Move-Item -LiteralPath "$configPath.pending" -Destination $configPath -Force
                    $configured = $true
                }
            }
        }
        $bitmap = Join-Path $recordings 'pairing.bmp'
        $target = Join-Path $RunDirectory 'pairing.bmp'
        if ((Test-Path -LiteralPath $bitmap) -and -not (Test-Path -LiteralPath $target)) { [IO.File]::Copy($bitmap, $target) }
        Start-Sleep -Milliseconds 200
    }
    $process.ControlInput.Close()
    if (-not $process.WaitForExit(10000)) { throw 'Receiver stop exceeded ten seconds. Recording integrity is unverified.' }
    if ($process.ExitCode -ne 0) { throw 'Receiver failed. Check the selected network interface and whether another receiver is using its port.' }
    if (Test-Path -LiteralPath (Join-Path $RunDirectory 'forget')) {
        if (Test-Path -LiteralPath $secretPath) { Remove-Item -LiteralPath $secretPath }
        Publish-Text 'Pairing reset. Start and scan the new QR code. Recordings remain saved.'
    } else { Publish-Text 'Receiver stopped. Recordings remain saved.' }
} catch {
    Publish-Text ('Receiver error: ' + $_.Exception.Message)
    exit 1
} finally {
    if ($process) {
        if (-not $process.HasExited) {
            $process.ControlInput.Close()
            if (-not $process.WaitForExit(2000)) { $process.Kill(); $process.WaitForExit() }
        }
        $process.Dispose()
    }
    foreach ($directory in @($RunDirectory, $recordings)) {
        if ($directory) {
            foreach ($name in @('pairing.html','pairing.bmp')) {
                $path = Join-Path $directory $name
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            }
        }
    }
    if ($lock) { $lock.Dispose() }
}

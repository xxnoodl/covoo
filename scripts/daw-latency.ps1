param([string]$AbletonRoot = (Join-Path $env:APPDATA 'Ableton'))

function Get-AbletonAudioState($Lines) {
    $current = $null
    $latest = $null
    foreach ($line in $Lines) {
        $position = $line.IndexOf('Audio In Out: ')
        if ($position -lt 0) { continue }
        $body = $line.Substring($position + 14)
        if ($body -eq 'Begin of UpdateAudioStateStatic') {
            $current = @{ log_timestamp = ($line.Substring(0, $position) -split ': info:')[0] }
        } elseif ($body -eq 'End of UpdateAudioStateStatic') {
            if ($current) {
                $valid = $true
                foreach ($name in @('Input Latency', 'Output Latency', 'Input Buffer Size', 'Output Buffer Size', 'Sample Rate')) {
                    $number = [double]0
                    $text = [string]$current[$name]
                    $first = ($text -split ' ')[0]
                    if (-not [double]::TryParse($first, [Globalization.NumberStyles]::Float,
                            [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
                        [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -le 0) { $valid = $false }
                }
                foreach ($name in @('Input Device', 'Output Device', 'Driver Type')) {
                    if (-not $current[$name] -or $current[$name] -eq 'No Device') { $valid = $false }
                }
                if ($valid) { $latest = [pscustomobject]$current }
            }
            $current = $null
        } elseif ($null -ne $current -and $body.Contains(': ')) {
            $parts = $body -split ': ', 2
            # Keep audio configuration only; never expose arbitrary log content.
            if ($parts[0] -in @('Driver Type', 'Input Device', 'Output Device', 'Sample Rate',
                    'Input Latency', 'Output Latency', 'Input Buffer Size', 'Output Buffer Size', 'Overall Latency')) {
                $current[$parts[0]] = $parts[1]
            }
        }
    }
    return $latest
}

function Get-DawLatencyAudit([string]$Root) {
    $logs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $path = Join-Path $_.FullName 'Preferences\Log.txt'
        if (Test-Path -LiteralPath $path) { Get-Item -LiteralPath $path }
    } | Sort-Object LastWriteTimeUtc -Descending)
    $entries = @()
    foreach ($log in $logs) {
        try {
            # Live can keep/rotate this file open. Read a bounded snapshot without
            # denying its writer or returning private project/plugin log lines.
            $stream = [IO.File]::Open($log.FullName, 'Open', 'Read', 'ReadWrite,Delete')
            try {
                $length = [int][Math]::Min($stream.Length, 8MB)
                $bytes = New-Object byte[] $length
                $stream.Seek(-$length, [IO.SeekOrigin]::End) | Out-Null
                $read = 0
                while ($read -lt $length) {
                    $count = $stream.Read($bytes, $read, $length - $read)
                    if ($count -eq 0) { break }
                    $read += $count
                }
                $lines = [Text.Encoding]::UTF8.GetString($bytes, 0, $read) -split '\r?\n'
                $state = Get-AbletonAudioState $lines
            } finally { $stream.Dispose() }
            $entries += [pscustomobject]@{ version = $log.Directory.Parent.Name;
                log_modified_utc = $log.LastWriteTimeUtc.ToString('o'); state = $state; error = $null }
        } catch {
            $entries += [pscustomobject]@{ version = $log.Directory.Parent.Name;
                log_modified_utc = $log.LastWriteTimeUtc.ToString('o'); state = $null; error = 'Log could not be read.' }
        }
    }
    return [pscustomobject]@{
        physical_monitoring_latency_ms = $null
        ableton_running = [bool](Get-Process -Name 'Ableton Live*' -ErrorAction SilentlyContinue)
        logs = $entries
        note = 'Historical logged settings, not proof of current configuration. DAW figures exclude upstream phone/network/Covoo buffering.'
    }
}

function Format-DawLatencyAudit($Audit) {
    $text = @('Ableton monitoring path', '', $Audit.note,
        'Physical monitoring delay: not measured.',
        ('Live process observed: ' + [string]$Audit.ableton_running), '')
    if (-not @($Audit.logs).Count) { $text += 'No Ableton log found for this Windows account.' }
    foreach ($entry in $Audit.logs) {
        $text += @($entry.version, ('Log modified (UTC): ' + $entry.log_modified_utc))
        if (-not $entry.state) { $text += @('No complete active audio configuration available.', ''); continue }
        $state = $entry.state
        $text += @('Last active configuration logged: ' + $state.log_timestamp)
        foreach ($name in @('Driver Type', 'Input Device', 'Output Device', 'Sample Rate',
                'Input Buffer Size', 'Input Latency', 'Output Buffer Size', 'Output Latency', 'Overall Latency')) {
            $value = $state.$name
            if (-not $value) { $value = 'Not reported' }
            $text += $name + ': ' + $value
        }
        $text += ''
    }
    $text += @('Next comparison:',
        'Use a blank Live set without effects/lookahead. Check the driver buffer in Hardware Setup.',
        'Reduced Latency When Monitoring can remove compensation from other tracks; it does not remove driver buffering or the monitored effects.',
        'The Covoo output profile changes only the receiver stage. Lower source targets are not a promised total latency.',
        'Driver registrations do not prove usable hardware or access to the phone/cable input.',
        'No DAW, driver, firewall or system settings were changed by this check.')
    return $text -join [Environment]::NewLine
}

if ($MyInvocation.InvocationName -ne '.') {
    $audit = Get-DawLatencyAudit $AbletonRoot
    $json = $audit | ConvertTo-Json -Depth 6
    $bytes = [Text.Encoding]::UTF8.GetBytes($json + [Environment]::NewLine)
    [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
}

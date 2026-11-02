$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'receiver-profiles.ps1')
. (Join-Path $PSScriptRoot 'daw-latency.ps1')
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function New-AudioBlock([string]$InputLatency, [bool]$Complete = $true) {
    $lines = @('date: info: Audio In Out: Begin of UpdateAudioStateStatic',
        'date: info: Audio In Out: Driver Type: ASIO',
        'date: info: Audio In Out: Input Device: synthetic',
        'date: info: Audio In Out: Output Device: synthetic',
        'date: info: Audio In Out: Sample Rate: 48000',
        ('date: info: Audio In Out: Input Latency: ' + $InputLatency + ' ms'),
        'date: info: Audio In Out: Output Latency: 60.0 ms',
        'date: info: Audio In Out: Input Buffer Size: 256 Samples',
        'date: info: Audio In Out: Output Buffer Size: 256 Samples',
        'date: info: Audio In Out: Overall Latency: 106 ms',
        'date: info: Audio In Out: Private project content: must-not-escape')
    if ($Complete) { $lines += 'date: info: Audio In Out: End of UpdateAudioStateStatic' }
    return $lines
}
$lines = @(New-AudioBlock '46.0') + @(New-AudioBlock '0') + @(New-AudioBlock 'NaN') + @(New-AudioBlock '999' $false)
$state = Get-AbletonAudioState $lines
Assert-True ($state.'Input Latency' -eq '46.0 ms') 'Shutdown/invalid/partial state replaced the last active block.'
Assert-True (-not ($state | ConvertTo-Json).Contains('must-not-escape')) 'Private log lines escaped.'
Assert-True ($null -eq (Get-AbletonAudioState @('unrelated log'))) 'Missing data became a configuration.'

$oldCulture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = New-Object Globalization.CultureInfo('fr-FR')
    Assert-True ((Get-AbletonAudioState $lines).'Input Latency' -eq '46.0 ms') 'Numeric parsing depends on Windows locale.'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $oldCulture }

$folder = Join-Path (Split-Path -Parent $PSScriptRoot) ('build\latency-check-' + [guid]::NewGuid().ToString('N'))
$preferences = Join-Path $folder 'Live synthetic\Preferences'
[IO.Directory]::CreateDirectory($preferences) | Out-Null
$path = Join-Path $preferences 'Log.txt'
[IO.File]::WriteAllText($path, ($lines -join "`r`n"))
$writer = [IO.File]::Open($path, 'Open', 'ReadWrite', 'ReadWrite,Delete')
try {
    $audit = Get-DawLatencyAudit $folder
    Assert-True ($audit.logs[0].state.'Overall Latency' -eq '106 ms') 'A log held by Live could not be read.'
    Assert-True ($null -eq $audit.physical_monitoring_latency_ms) 'Reported driver figures became a physical measurement.'
    $text = Format-DawLatencyAudit $audit
    Assert-True ($text.Contains('Input Latency: 46.0 ms') -and $text.Contains('Overall Latency: 106 ms')) 'Audio figures are not readable.'
    Assert-True ($text.Contains('Log modified (UTC): 2') -and $text.Contains('Live process observed: ')) 'Snapshot labels are split from values.'
} finally { $writer.Dispose() }
$missing = Get-DawLatencyAudit (Join-Path $folder 'missing')
Assert-True (@($missing.logs).Count -eq 0 -and $null -eq $missing.physical_monitoring_latency_ms) 'Missing logs produced measurements.'
Assert-True ((Format-DawLatencyAudit $missing).Contains('No Ableton log found')) 'Missing log is not explicit.'

$device = 'Endpoint with "quotes" and spaces'
$compatible = @(Get-ReceiverRouteArguments $device 'compatible')
Assert-True ($compatible[1] -eq $device -and $compatible[3] -eq 'legacy' -and $compatible[5] -eq '40') 'Compatibility route changed.'
$fast = @(Get-ReceiverRouteArguments $device 'fast')
Assert-True ($fast[1] -eq $device -and $fast[3] -eq 'low-period' -and $fast[5] -eq '8' -and $fast[7] -eq '128') 'Fast mode does not reach engine arguments.'
Assert-True (@(Get-ReceiverRouteArguments '' 'fast').Count -eq 0) 'File-only mode includes audio flags.'
$monitor = @(Get-ReceiverMonitorArguments $device 'balanced')
Assert-True ($monitor[0] -eq '--monitor-device' -and $monitor[1] -eq $device -and $monitor[4] -eq '--monitor-buffer-ms' -and $monitor[5] -eq '16') 'Monitor profile changes the main route arguments.'
$rejected = $false
try { Get-ReceiverRouteArguments $device 'unknown' | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'Unknown saved profile silently fell back.'
Write-Host 'Latency state parsing, shared log reads, locale/unknown/privacy handling and independent output profiles passed. No audio endpoint opened.'

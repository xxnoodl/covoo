$ErrorActionPreference = 'Stop'
$receiver = Join-Path $PSScriptRoot 'covoo-receiver.exe'
if (-not (Test-Path -LiteralPath $receiver)) {
    throw 'Extract the receiver package before running this launcher.'
}
Write-Host 'Direct headphone comparison. Close the other receiver and Ableton first.'
Write-Host 'Use wired PC headphones at low volume. Do not select speakers or CABLE Input.'
Write-Host 'On Realtek, headphones may share the endpoint named Speakers. Check the physical output.'
& $receiver --list-audio
if ($LASTEXITCODE -ne 0) { throw 'Could not list audio outputs.' }
$endpoint = Read-Host 'Paste the exact headphone endpoint name (without the format details)'
if ([string]::IsNullOrWhiteSpace($endpoint)) { throw 'No output selected.' }
if ($endpoint -match '(?i)CABLE|VB-Audio|Bluetooth|AirPods') {
    throw 'Use a wired physical headphone endpoint for this comparison.'
}
Write-Host "Selected output: $endpoint"
$confirmation = Read-Host 'Confirm wired headphones are connected, volume is low and Ableton is closed. Type YES'
if ($confirmation -cne 'YES') { throw 'Comparison cancelled.' }
& $receiver --probe-audio $endpoint
if ($LASTEXITCODE -ne 0) { throw 'Selected output could not be queried. No fallback was used.' }
Write-Host 'Scan the new QR. Keep phone Low latency and Save enabled.'
Write-Host 'The requested 128-frame period may be rounded up by this device. Full latency is not measured.'
& $receiver --serve --audio-device $endpoint --audio-backend low-period --buffer-ms 8 --device-buffer-frames 128 --output (Join-Path $PSScriptRoot 'recordings')
if ($LASTEXITCODE -ne 0) { throw 'Receiver stopped with an error. Keep the terminal message.' }

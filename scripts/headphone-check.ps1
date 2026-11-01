param([ValidateSet('legacy', 'low-period')][string]$Backend = 'legacy')
$ErrorActionPreference = 'Stop'
$receiver = Join-Path $PSScriptRoot 'covoo-receiver.exe'
if (-not (Test-Path -LiteralPath $receiver)) {
    throw 'Extract the receiver package before running this launcher.'
}
Write-Host 'Direct headphone comparison. Close the other receiver and Ableton first.'
Write-Host "Output backend: $Backend. Legacy is the compatibility comparison; low-period remains experimental."
Write-Host 'Use wired PC headphones at low volume. Do not use loudspeakers or CABLE Input.'
Write-Host 'On Realtek, headphones may share the endpoint named Speakers. Check the physical output.'
$deviceLines = @(& $receiver --list-audio)
if ($LASTEXITCODE -ne 0) { throw 'Could not list audio outputs.' }
$endpoints = @($deviceLines | ForEach-Object {
    if ($_ -match '^(.*): \d+ Hz, \d+ channels, \S+$') { $Matches[1] }
})
if ($endpoints.Count -eq 0) { throw 'No supported output names were listed.' }
for ($index = 0; $index -lt $endpoints.Count; $index++) {
    Write-Host ("{0}. {1}" -f ($index + 1), $endpoints[$index])
}
$selection = (Read-Host 'Enter the headphone output number or paste its name').Trim()
$number = 0
if ([int]::TryParse($selection, [ref]$number)) {
    if ($number -lt 1 -or $number -gt $endpoints.Count) { throw 'Output number is not in the list.' }
    $endpoint = $endpoints[$number - 1]
} else {
    $selection = $selection -replace ': \d+ Hz, \d+ channels, \S+$', ''
    $matchesFound = @($endpoints | Where-Object { $_ -ceq $selection })
    if ($matchesFound.Count -ne 1) { throw 'Choose one exact output from the list.' }
    $endpoint = $matchesFound[0]
}
if ($endpoint -match '(?i)CABLE|VB-Audio|Bluetooth|AirPods') {
    throw 'Use a wired physical headphone endpoint for this comparison.'
}
Write-Host "Selected output: $endpoint"
$confirmation = Read-Host 'Confirm wired headphones are connected, volume is low and Ableton is closed. Type YES'
if ($confirmation.Trim() -ine 'YES') { Write-Host 'Comparison cancelled.'; return }
if ($Backend -eq 'low-period') {
    & $receiver --probe-audio $endpoint
    if ($LASTEXITCODE -ne 0) { throw 'Selected output could not be queried. No fallback was used.' }
}
Write-Host 'Scan the new QR. Keep phone Low latency and Save enabled.'
Write-Host 'The requested 128-frame buffer may be adjusted by the device. Full latency is not measured.'
& $receiver --serve --audio-device $endpoint --audio-backend $Backend --buffer-ms 8 --device-buffer-frames 128 --output (Join-Path $PSScriptRoot 'recordings')
if ($LASTEXITCODE -ne 0) { throw 'Receiver stopped with an error. Keep the terminal message.' }

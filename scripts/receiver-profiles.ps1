# Receiver requests only; no device/DAW settings or end-to-end latency claims.
function Get-ReceiverProfiles {
    @(
        [pscustomobject]@{ id = 'compatible'; name = 'Compatibility'; backend = 'legacy'; buffer = 40; frames = $null;
            note = '40 ms source target using the compatibility backend.' }
        [pscustomobject]@{ id = 'balanced'; name = 'Lower latency (experimental)'; backend = 'low-period'; buffer = 16; frames = 128;
            note = '16 ms source target with a low-period output request. Actual endpoint limits may be higher.' }
        [pscustomobject]@{ id = 'fast'; name = 'Minimum buffering (experimental)'; backend = 'low-period'; buffer = 8; frames = 128;
            note = '8 ms source target with a low-period output request. More sensitive to arrival gaps; actual buffering may be higher.' }
    )
}

function Get-ReceiverRouteArguments([string]$Device, [string]$ProfileId) {
    if (-not $Device) { return @() }
    $profile = Get-ReceiverProfiles | Where-Object id -eq $ProfileId
    if (-not $profile) { throw 'Unknown receiver profile. Select a profile explicitly.' }
    $arguments = @('--audio-device', $Device, '--audio-backend', $profile.backend,
        '--buffer-ms', [string]$profile.buffer)
    if ($null -ne $profile.frames) { $arguments += @('--device-buffer-frames', [string]$profile.frames) }
    return $arguments
}

function Get-ReceiverMonitorArguments([string]$Device, [string]$ProfileId) {
    $arguments = @(Get-ReceiverRouteArguments $Device $ProfileId)
    $names = @{ '--audio-device' = '--monitor-device'; '--audio-backend' = '--monitor-backend';
        '--buffer-ms' = '--monitor-buffer-ms'; '--device-buffer-frames' = '--monitor-device-buffer-frames' }
    for ($index = 0; $index -lt $arguments.Count; $index += 2) { $arguments[$index] = $names[$arguments[$index]] }
    return $arguments
}

param([string]$ReceiverPath = 'target/debug/windows-receiver.exe',
    [string]$HostPath = 'build/vst3-prototype/bin/Release/covoo_editor_host.exe',
    [string]$ClientPath = 'target/debug/examples/managed_take_fixture.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'desktop-common.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $repo ('build/vst3-fault-check-' + [guid]::NewGuid().ToString('N'))))
$binary = Join-Path $root 'Contents/x86_64-win'
$runtime = Join-Path $root 'Contents/Resources/runtime'
[IO.Directory]::CreateDirectory($binary) | Out-Null
[IO.Directory]::CreateDirectory($runtime) | Out-Null
Copy-Item -LiteralPath $HostPath -Destination (Join-Path $binary 'fault-host.exe')
Copy-Item -LiteralPath $ReceiverPath -Destination (Join-Path $runtime 'covoo-receiver.exe')
foreach ($name in @('desktop-common.ps1', 'plugin-session.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $runtime }
$ClientPath = (Resolve-Path -LiteralPath $ClientPath).Path
$savedAppData = $env:LOCALAPPDATA
$savedLinks = $env:COVOO_VST3_LINK_DIRECTORY
$holders = New-Object 'Collections.Generic.List[object]'
$clients = New-Object 'Collections.Generic.List[object]'
$watched = New-Object 'Collections.Generic.List[object]'
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Wait-File([string]$Path, $Process) {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $Path)) {
        if ($Process.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw "Fixture failed before ready. Evidence: $root" }
        Start-Sleep -Milliseconds 50
    }
}
function Capture($Process, [string]$Name) {
    $Process | Add-Member -NotePropertyName OutTask -NotePropertyValue $Process.StandardOutput.ReadToEndAsync()
    $Process | Add-Member -NotePropertyName ErrTask -NotePropertyValue $Process.StandardError.ReadToEndAsync()
    $Process | Add-Member -NotePropertyName EvidenceName -NotePropertyValue $Name
}
function Start-Holder([string]$Name) {
    $ready = Join-Path $root "$Name.ready"
    $process = New-ReceiverProcess (Join-Path $binary 'fault-host.exe') @('--fault-holder', $ready, (Join-Path $root 'public-state.bin'))
    Capture $process $Name
    $holders.Add($process)
    Wait-File $ready $process
    $instance = [IO.File]::ReadAllText($ready).Trim()
    Require ($instance -cmatch '^[0-9a-f]{32}$') 'Invalid fixture instance.'
    $run = Join-Path $env:LOCALAPPDATA "covoo/vst3-runs/$instance"
    $recordings = [IO.File]::ReadAllText((Join-Path $run 'recordings.txt'))
    Require ([IO.Path]::GetFullPath($recordings).StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) 'Unexpected recordings path.'
    return @{ process = $process; instance = $instance; recordings = $recordings; ready = $ready; run = $run }
}
function Start-Client($Holder, [int]$Port, [string]$PrivateRecord, [string]$Mode) {
    $ready = Join-Path $root ($Mode + '-' + $Holder.instance + '.ready')
    $process = New-ReceiverProcess $ClientPath @([string]$Port, $ready, $Mode)
    Capture $process ('client-' + $Mode)
    $clients.Add($process)
    $process.ControlInput.WriteLine($PrivateRecord)
    $process.ControlInput.Close()
    Wait-File $ready $process
    Require (-not $process.HasExited) 'Client exited before fault injection.'
    return $process
}
function Recording-Audit($Holder, [string]$Name) {
    $text = & python (Join-Path $PSScriptRoot 'recording-health.py') $Holder.recordings
    Require ($LASTEXITCODE -eq 0) 'Recording audit failed.'
    [IO.File]::WriteAllText((Join-Path $root "$Name-audit.json"), ($text -join "`n"))
    return (($text -join "`n") | ConvertFrom-Json)
}
function Wait-RecordingBytes($Holder, $Client) {
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline -and -not $Holder.process.HasExited -and -not $Client.HasExited) {
        $wave = Get-ChildItem -LiteralPath $Holder.recordings -Filter '*.wav' | Select-Object -First 1
        if ($wave) {
            # Directory metadata can lag an open writer on Windows; inspect the handle length.
            $stream = [IO.File]::Open($wave.FullName, 'Open', 'Read', 'ReadWrite')
            try { if ($stream.Length -gt 44) { return $stream.Length } } finally { $stream.Dispose() }
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'No active synthetic recording bytes before crash.'
}
try {
    $env:LOCALAPPDATA = Join-Path $root 'user-data'
    $env:COVOO_VST3_LINK_DIRECTORY = Join-Path $root 'links'
    $first = Start-Holder 'crash'
    $profile = Join-Path $env:LOCALAPPDATA ('covoo/vst3-receivers/' + $first.instance)
    $secret = Join-Path $profile 'pairing.dpapi'
    $privateBefore = Read-Pairing $secret
    $port = [int]((Get-Content -LiteralPath (Join-Path $profile 'connection.json') -Raw | ConvertFrom-Json).port)
    $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $port -State Listen | Select-Object -First 1
    $receiver = [Diagnostics.Process]::GetProcessById($listener.OwningProcess)
    $null = $receiver.Handle # Retain identity across exit/PID reuse.
    Require ($receiver.MainModule.FileName -eq (Join-Path $runtime 'covoo-receiver.exe')) 'Unexpected receiver owner.'
    $meta = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $receiver.Id)
    $broker = [Diagnostics.Process]::GetProcessById($meta.ParentProcessId)
    $null = $broker.Handle
    $watched.Add($receiver); $watched.Add($broker)
    $client = Start-Client $first $port $privateBefore 'hold'
    $bytesBeforeCrash = Wait-RecordingBytes $first $client
    $first.process.Kill() # Only the fixture created above; never Live or a real receiver.
    Require ($first.process.WaitForExit(5000)) 'Fault host did not exit.'
    Require ($receiver.WaitForExit(5000) -and $broker.WaitForExit(5000)) 'Lifetime job left an orphan.'
    Require ($client.WaitForExit(8000) -and $client.ExitCode -eq 0) 'Client did not observe forced disconnection.'
    $crashed = Recording-Audit $first 'crash'
    Require ($crashed.recordings.Count -gt 0) 'Crash recording was hidden from the audit.'
    Require (@($crashed.recordings | Where-Object { $_.state -eq 'finalized_contiguous_segment' }).Count -eq 0) 'Crash was falsely accepted as finalized.'
    $second = Start-Holder 'restart'
    Require ($second.instance -ne $first.instance) 'Restart reused the crashed bridge identity.'
    Require ((Read-Pairing $secret) -eq $privateBefore) 'Saved pairing changed after restart.'
    $restoredPort = [int]((Get-Content -LiteralPath (Join-Path $profile 'connection.json') -Raw | ConvertFrom-Json).port)
    Require ($restoredPort -eq $port) 'Saved loopback port changed after crash.'
    $cleanClient = Start-Client $second $port $privateBefore 'finish'
    Require ($cleanClient.WaitForExit(10000) -and $cleanClient.ExitCode -eq 0) 'Fresh take did not complete after crash.'
    $clean = Recording-Audit $second 'restart'
    Require ($clean.recordings.Count -eq 1 -and $clean.recordings[0].state -eq 'finalized_contiguous_segment') 'Fresh take archive was not finalized.'
    [IO.File]::WriteAllText([IO.Path]::ChangeExtension($second.ready, '.stop'), 'stop')
    Require ($second.process.WaitForExit(15000) -and $second.process.ExitCode -eq 0) 'Restored host did not stop cleanly.'
    [IO.File]::WriteAllText((Join-Path $root 'result.json'), (@{ host_crash_cleanup = $true; interrupted_archive_not_accepted = $true;
        saved_pairing_and_port_restored = $true; fresh_take_finalized = $true;
        bytes_on_disk_before_crash = $bytesBeforeCrash; physical_accepted = $false } | ConvertTo-Json))
    Write-Host "Isolated active-take host crash, child cleanup, archive audit and restart passed. Evidence: $root"
} finally {
    foreach ($process in @($clients.ToArray()) + @($holders.ToArray())) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        [IO.File]::WriteAllText((Join-Path $root ($process.EvidenceName + '.log')), $process.OutTask.Result + $process.ErrTask.Result)
        $process.Dispose()
    }
    foreach ($process in $watched) { $process.Dispose() }
    # Remove only fixture credential artifacts under the verified build root.
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.Name -in @('pairing.html', 'pairing.bmp') -or $_.Extension -in @('.link', '.dpapi') }) {
        Require ($file.FullName.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) 'Credential cleanup escaped fixture root.'
        Remove-Item -LiteralPath $file.FullName
    }
    $env:LOCALAPPDATA = $savedAppData
    $env:COVOO_VST3_LINK_DIRECTORY = $savedLinks
}

param(
    [string]$ReceiverPath = 'target/debug/windows-receiver.exe',
    [string]$HostPath = 'build/vst3-prototype/bin/Release/covoo_bridge_host.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'desktop-common.ps1')
$receiver = (Resolve-Path -LiteralPath $ReceiverPath).Path
$hostExe = (Resolve-Path -LiteralPath $HostPath).Path
$root = Join-Path $repo ('build/vst3-bridge-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$previousDirectory = $env:COVOO_VST3_LINK_DIRECTORY
$env:COVOO_VST3_LINK_DIRECTORY = Join-Path $root 'links'
function Run-Client([string[]]$ClientArgs, [bool]$Success, [string]$Log) {
    $process = New-ReceiverProcess $receiver $ClientArgs
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            $process.Kill(); $process.WaitForExit()
            [IO.File]::WriteAllText((Join-Path $root $Log), $stdout.Result + $stderr.Result)
            throw "Bridge client timed out. See $root\$Log"
        }
        $output = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $root $Log), $output)
        if (($process.ExitCode -eq 0) -ne $Success) { throw "Bridge client result unexpected. See $root\$Log" }
        return $output
    } finally { $process.ControlInput.Dispose(); $process.Dispose() }
}
try {
    foreach ($rate in @(48000, 44100, 96000)) {
        $stopFile = Join-Path $root "stop-$rate"
        $hostProcess = New-ReceiverProcess $hostExe @("$rate", $stopFile)
        try {
            $ready = $hostProcess.StandardOutput.ReadLineAsync()
            if (-not $ready.Wait(5000) -or $ready.Result -notmatch '^[0-9a-f]{32}$') { throw 'Bridge host did not publish an instance ID.' }
            $id = $ready.Result
            $hostOutput = $hostProcess.StandardOutput.ReadToEndAsync()
            $hostError = $hostProcess.StandardError.ReadToEndAsync()
            $link = Join-Path $env:COVOO_VST3_LINK_DIRECTORY "$id.link"
            $acl = Get-Acl -LiteralPath $link
            if (-not $acl.AreAccessRulesProtected) { throw 'Link ACL inherited external access.' }
            $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            foreach ($rule in $acl.Access) {
                if ($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $userSid) {
                    throw 'Link ACL grants another principal access.'
                }
            }
            $probe = Run-Client @('--probe-plugin', $id) $true "probe-$rate.log" | ConvertFrom-Json
            if (-not $probe.authenticated -or $probe.host_rate -ne $rate) { throw 'Authenticated feedback differs from host setup.' }
            Start-Sleep -Milliseconds 30
            if ($rate -eq 48000) {
                $record = [IO.File]::ReadAllBytes($link)
                $bad = [byte[]]$record.Clone(); $bad[40] = $bad[40] -bxor 1
                try {
                    [IO.File]::WriteAllBytes($link, $bad)
                    Run-Client @('--probe-plugin', $id) $false 'wrong-credential.log' | Out-Null
                } finally { [IO.File]::WriteAllBytes($link, $record) }
                Start-Sleep -Milliseconds 30
                Run-Client @('--probe-plugin', ('0' * 32)) $false 'missing-instance.log' | Out-Null
                # A client with no credential must never receive the auth ACK.
                $unauthorized = New-Object IO.Pipes.NamedPipeClientStream('.', "covoo-vst3-$id", [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
                try {
                    $unauthorized.Connect(500)
                    $hello = New-Object byte[] 40
                    [Text.Encoding]::ASCII.GetBytes('CVB1').CopyTo($hello, 0); $hello[4] = 1
                    $unauthorized.Write($hello, 0, 40)
                    $reply = New-Object byte[] 72; $received = 0
                    while ($received -lt 72) {
                        $read = $unauthorized.ReadAsync($reply, $received, 72 - $received)
                        if (-not $read.Wait(1000) -or $read.Result -eq 0) { throw 'Server authentication response stalled.' }
                        $received += $read.Result
                    }
                    $unauthorized.Write((New-Object byte[] 32), 0, 32)
                    $ack = New-Object byte[] 4
                    $rejected = $false
                    try {
                        $read = $unauthorized.ReadAsync($ack, 0, 4)
                        if (-not $read.Wait(1000)) { throw 'Client rejection stalled.' }
                        $rejected = $read.Result -eq 0
                    } catch [AggregateException] { $rejected = $true }
                    if (-not $rejected) { throw 'Server accepted an invalid client proof.' }
                } finally { $unauthorized.Dispose() }
                Start-Sleep -Milliseconds 30
                # A spoof server that never authenticates must not hold a client.
                $fakeId = [guid]::NewGuid().ToString('N')
                $fakeRecord = [byte[]]$record.Clone()
                [Text.Encoding]::ASCII.GetBytes($fakeId).CopyTo($fakeRecord, 8)
                [Array]::Clear($fakeRecord, 40, 32)
                $fakeLink = Join-Path $env:COVOO_VST3_LINK_DIRECTORY "$fakeId.link"
                # PID is part of the server identity check, independent of HMAC.
                [BitConverter]::GetBytes([uint32]$PID).CopyTo($fakeRecord, 72)
                [IO.File]::WriteAllBytes($fakeLink, $fakeRecord); Set-Acl -LiteralPath $fakeLink -AclObject $acl
                $spoof = New-Object IO.Pipes.NamedPipeServerStream("covoo-vst3-$fakeId", [IO.Pipes.PipeDirection]::InOut, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
                try {
                    $accept = $spoof.WaitForConnectionAsync()
                    $timer = [Diagnostics.Stopwatch]::StartNew()
                    Run-Client @('--probe-plugin', $fakeId) $false 'stalled-server.log' | Out-Null
                    if ($timer.ElapsedMilliseconds -gt 2000 -or -not $accept.IsCompleted) { throw 'Stalled server exceeded the operation deadline.' }
                } finally { $spoof.Dispose(); Remove-Item -LiteralPath $fakeLink }
            }
            Run-Client @('--self-test-plugin', $id) $true "loopback-$rate.log" | Out-Null
            [IO.File]::WriteAllText($stopFile, 'stop')
            if (-not $hostProcess.WaitForExit(5000)) { throw 'Bridge host teardown timed out.' }
            [IO.File]::WriteAllText((Join-Path $root "host-$rate.log"), $hostOutput.Result + $hostError.Result)
            if ($hostProcess.ExitCode -ne 0) { throw "Bridge host audio/lifecycle check failed. See $root\host-$rate.log" }
            if (Test-Path -LiteralPath $link) { throw 'Clean host exit retained a credential file.' }
            Write-Host "Authenticated TLS/UDP to VST source passed at host $rate Hz. Archive samples remain exact."
        } finally {
            if (-not $hostProcess.HasExited) { $hostProcess.Kill(); $hostProcess.WaitForExit() }
            $hostProcess.ControlInput.Dispose(); $hostProcess.Dispose()
        }
    }
} finally { $env:COVOO_VST3_LINK_DIRECTORY = $previousDirectory }
Write-Host 'Bridge synthetic checks passed. No Live session, physical endpoint or latency measurement.'
